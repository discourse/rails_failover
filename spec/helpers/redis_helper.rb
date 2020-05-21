module RedisHelper
  require 'redis'

  def create_redis_client
    Redis.new(
      host: "127.0.0.1",
      port: 6381,
      replica_host: "127.0.0.1",
      replica_port: 6382,
      connector: RailsFailover::Redis::Connector
    )
  end
end
