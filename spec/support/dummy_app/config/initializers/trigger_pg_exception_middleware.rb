class TriggerPGException
  def initialize(app)
    @app = app
  end

  def call(env)
    if env["REQUEST_PATH"] == "/trigger-middleware-pg-exception"
      RailsFailover::ActiveRecord.on_failover do |role|
        Post.create!(body: "triggered_from_pg_exception:#{role}")
      end
      raise ::PG::UnableToSend
    else
      @app.call(env)
    end
  end
end

Rails.application.middleware.insert_after RailsFailover::ActiveRecord::Middleware,
                                          TriggerPGException
