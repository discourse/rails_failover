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
        writing_role = ::ActiveRecord::Base.writing_role

        role =
          if primary_down = Handler.instance.primary_down?(writing_role) || self.class.force_reading_role_callback&.call(env)
            ::ActiveRecord::Base.reading_role
          else
            ::ActiveRecord::Base.writing_role
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
