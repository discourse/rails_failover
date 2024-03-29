# frozen_string_literal: true

module RailsFailover
  module ActiveRecord
    class Interceptor
      def self.adapter_errors
        @adapter_errors ||=
          begin
            if defined?(::PG)
              [::PG::UnableToSend, ::PG::ConnectionBad]
            elsif defined?(::Mysql2)
              [::Mysql2::Error::ConnectionError]
            end
          end
      end

      def self.handle(request, exception)
        verify_primary(exception, request.env[Middleware::WRITING_ROLE_HEADER])
      end

      def self.verify_primary(exception, writing_role)
        exception = resolve_cause(exception)

        if adapter_errors.any? { |error| exception.is_a?(error) }
          Handler.instance.verify_primary(writing_role)
        end
      end

      def self.resolve_cause(exception)
        exception.cause ? resolve_cause(exception.cause) : exception
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
        current_role = ::ActiveRecord::Base.current_role || RailsFailover::ActiveRecord.writing_role
        is_writing_role = current_role.to_s.end_with?(RailsFailover::ActiveRecord.writing_role.to_s)
        writing_role = resolve_writing_role(current_role, is_writing_role)

        role =
          if self.class.force_reading_role_callback&.call(env) ||
               Handler.instance.primary_down?(writing_role)
            reading_role = resolve_reading_role(current_role, is_writing_role)
            ensure_reading_connection_established!(
              writing_role: writing_role,
              reading_role: reading_role,
            )
            reading_role
          else
            writing_role
          end

        ::ActiveRecord::Base.connected_to(role: role) do
          env[CURRENT_ROLE_HEADER] = role
          env[WRITING_ROLE_HEADER] = writing_role
          @app.call(env)
        end
      rescue => e
        Interceptor.verify_primary(e, writing_role) if writing_role
        raise e
      end

      private

      def ensure_reading_connection_established!(writing_role:, reading_role:)
        connection_handler = ::ActiveRecord::Base.connection_handler
        connection_handler
          .connection_pools(writing_role)
          .each do |connection_pool|
            config = connection_pool.db_config.configuration_hash
            RailsFailover::ActiveRecord.establish_reading_connection(
              connection_handler,
              config,
              role: reading_role,
            )
          end
      end

      def resolve_writing_role(current_role, is_writing_role)
        return current_role if is_writing_role
        current_role
          .to_s
          .sub(
            /#{RailsFailover::ActiveRecord.reading_role}$/,
            RailsFailover::ActiveRecord.writing_role.to_s,
          )
          .to_sym
      end

      def resolve_reading_role(current_role, is_writing_role)
        return current_role unless is_writing_role
        current_role
          .to_s
          .sub(
            /#{RailsFailover::ActiveRecord.writing_role}$/,
            RailsFailover::ActiveRecord.reading_role.to_s,
          )
          .to_sym
      end
    end
  end
end
