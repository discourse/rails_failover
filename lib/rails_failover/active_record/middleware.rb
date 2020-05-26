# frozen_string_literal: true

module RailsFailover
  module ActiveRecord
    class Middleware
      def initialize(app)
        @app = app
      end

      def call(env)
        writing_role = ::ActiveRecord::Base.writing_role

        role =
          if primary_down = Handler.instance.primary_down?(writing_role)
            ::ActiveRecord::Base.reading_role
          else
            ::ActiveRecord::Base.writing_role
          end

        ::ActiveRecord::Base.connected_to(role: role) do
          env["rails_failover.role"] = role
          @app.call(env)
        end
      rescue Exception => e
        if (resolve_cause(e).is_a?(::PG::Error))
          Handler.instance.verify_primary(writing_role)
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
