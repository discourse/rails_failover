# frozen_string_literal: true

module RailsFailover
  module ActiveRecord
    class Railtie < ::Rails::Railtie
      initializer "rails_failover.init", after: "active_record.initialize_database" do
        ::ActiveSupport.on_load(:active_record) do
          Handler.instance

          # We are doing this manually for now since we're awaiting Rails 6.1 to be released which will
          # have more stable ActiveRecord APIs for handling multiple databases with different roles.
          ::ActiveRecord::Base.connection_handlers[::ActiveRecord::Base.reading_role] =
            ::ActiveRecord::ConnectionAdapters::ConnectionHandler.new

          ::ActiveRecord::Base.connection_handlers[::ActiveRecord::Base.writing_role].connection_pools.each do |connection_pool|
            RailsFailover::ActiveRecord.establish_reading_connection(
              ::ActiveRecord::Base.connection_handlers[::ActiveRecord::Base.reading_role],
              connection_pool.spec
            )
          end

          begin
            ::ActiveRecord::Base.connection
          rescue ::ActiveRecord::NoDatabaseError
            # Do nothing since database hasn't been created
          rescue ::PG::Error => e
            Handler.instance.verify_primary(::ActiveRecord::Base.writing_role)
            ::ActiveRecord::Base.connection_handler = ::ActiveRecord::Base.lookup_connection_handler(:reading)
          end
        end
      end

      initializer "rails_failover.insert_middleware" do |app|
        ActionDispatch::DebugExceptions.register_interceptor do |request, exception|
          RailsFailover::ActiveRecord::Interceptor.handle(request, exception)
        end

        if !skip_middleware(app.config)
          app.middleware.unshift(::RailsFailover::ActiveRecord::Middleware)
        end
      end

      def skip_middleware?(config)
        return false if !config.respond_to?(:skip_rails_failover_active_record_middleware)
        config.skip_rails_failover_active_record_middleware
      end
    end
  end
end
