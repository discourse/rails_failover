class RoleSwitcher
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if role = request.params["role"]
      ActiveRecord::Base.connected_to(role: role.to_sym) do
        env["test"] = true
        @app.call(env)
      end
    else
      @app.call(env)
    end
  end
end

if Rails.application.config.active_record_rails_failover
  Rails.application.middleware.insert_before RailsFailover::ActiveRecord::Middleware, RoleSwitcher
end
