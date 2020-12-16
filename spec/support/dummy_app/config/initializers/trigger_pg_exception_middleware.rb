class TriggerPGException
  def initialize(app)
   @app = app
  end

  def call(env)
    if env["REQUEST_PATH"] == "/trigger-middleware-pg-exception"
      raise ::PG::UnableToSend
    else
      @app.call(env)
    end
  end
end

Rails.application.middleware.insert_after RailsFailover::ActiveRecord::Middleware, TriggerPGException
