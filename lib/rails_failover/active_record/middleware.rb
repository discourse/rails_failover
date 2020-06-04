# frozen_string_literal: true

module RailsFailover
  module ActiveRecord
    class Interceptor
      def self.adapter_error
        @adapter_error ||= begin
          if defined?(::PG)
            ::PG::Error
          elsif defined?(::Mysql2)
            ::Mysql2::Error
          end
        end
      end

      def self.handle(request, exception)
        if (resolve_cause(exception).is_a?(adapter_error))
          Handler.instance.verify_primary(request.env[Middleware::WRITING_ROLE_HEADER])
        end
      end

      def self.resolve_cause(exception)
        if exception.cause
          resolve_cause(exception.cause)
        else
          exception
        end
      end
    end

    class Middleware
      class << self
        attr_accessor :force_reading_role_callback
      end

      CURRENT_ROLE_HEADER = "rails_failover.role"
      WRITING_ROLE_HEADER = "rails_failover.writing_role"

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
          env[CURRENT_ROLE_HEADER] = role
          env[WRITING_ROLE_HEADER] = writing_role
          @app.call(env)
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
    end
  end
end
