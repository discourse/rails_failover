# frozen_string_literal: true

module RailsFailover
  module ActiveRecord
    class Railtie < ::Rails::Railtie
      initializer "rails_failover.init", after: "active_record.initialize_database" do |app|
        app.config.active_record_rails_failover = false
        config = RailsFailover::ActiveRecord.config
        break unless config[:replica_host] && config[:replica_port]

        app.config.active_record_rails_failover = true
        ::ActiveSupport.on_load(:active_record) do
          begin
            ::ActiveRecord::Base.connection
          rescue ::ActiveRecord::NoDatabaseError
            # Do nothing since database hasn't been created
          rescue ::PG::Error, ::ActiveRecord::ConnectionNotEstablished
            Handler.instance.verify_primary(RailsFailover::ActiveRecord.writing_role)
          end
        end
      end

      initializer "rails_failover.insert_middleware" do |app|
        if app.config.active_record_rails_failover
          ActionDispatch::DebugExceptions.register_interceptor do |request, exception|
            RailsFailover::ActiveRecord::Interceptor.handle(request, exception)
          end

          if !skip_middleware?(app.config)
            app.middleware.unshift(RailsFailover::ActiveRecord::Middleware)
          end
        end
      end

      def skip_middleware?(config)
        config.try(:skip_rails_failover_active_record_middleware)
      end
    end
  end
end
