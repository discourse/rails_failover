# frozen_string_literal: true

module RailsFailover
  module ActiveRecord
    class Middleware
      class << self
        attr_accessor :force_reading_role_callback

        def adapter_error
          @adapter_error ||= begin
            if defined?(::PG)
              ::PG::Error
            elsif defined?(::SQLite3)
              ::SQLite3::Exception
            elsif defined?(::Mysql2)
              ::Mysql2::Error
            end
          end
        end
      end

      ROLE_HEADER = "rails_failover.role"

      def initialize(app)
        @app = app
      end

      def call(env)
        current_role = ::ActiveRecord::Base.current_role || ::ActiveRecord::Base.writing_role
        is_writing_role = current_role.to_s.end_with?(::ActiveRecord::Base.writing_role.to_s)
        writing_role = resolve_writing_role(current_role, is_writing_role)

        role =
          if primary_down = self.class.force_reading_role_callback&.call(env) || Handler.instance.primary_down?(writing_role)
            reading_role = resolve_reading_role(current_role, is_writing_role)
            ensure_reading_connection_established!(writing_role: writing_role, reading_role: reading_role)
            reading_role
          else
            writing_role
          end

        ::ActiveRecord::Base.connected_to(role: role) do
          env[ROLE_HEADER] = role
          @app.call(env)
        end
      rescue Exception => e
        if (resolve_cause(e).is_a?(self.class.adapter_error))
          Handler.instance.verify_primary(writing_role)
          raise
        else
          raise
        end
      end

      private

      def ensure_reading_connection_established!(writing_role:, reading_role:)
        ::ActiveRecord::Base.connection_handlers[reading_role] ||= begin
          handler = ::ActiveRecord::ConnectionAdapters::ConnectionHandler.new

          ::ActiveRecord::Base.connection_handlers[writing_role].connection_pools.each do |pool|
            ::RailsFailover::ActiveRecord.establish_reading_connection(handler, pool.spec)
          end

          handler
        end
      end

      def resolve_writing_role(current_role, is_writing_role)
        if is_writing_role
          current_role
        else
          current_role.to_s.sub(
            /#{::ActiveRecord::Base.reading_role}$/,
            ::ActiveRecord::Base.writing_role.to_s
          ).to_sym
        end
      end

      def resolve_reading_role(current_role, is_writing_role)
        if is_writing_role
          current_role.to_s.sub(
            /#{::ActiveRecord::Base.writing_role}$/,
            ::ActiveRecord::Base.reading_role.to_s
          ).to_sym
        else
          current_role
        end
      end

      def resolve_cause(error)
        if error.cause
          resolve_cause(error.cause)
        else
          error
        end
      end
    end
  end
end
