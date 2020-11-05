# frozen_string_literal: true

module RedisHelper
  REDIS_PRIMARY_PORT = 6381
  REDIS_REPLICA_PORT = 6382
  def create_redis_client(opts = {})
    Redis.new({
      host: "127.0.0.1",
      port: REDIS_PRIMARY_PORT,
      replica_host: "127.0.0.1",
      replica_port: REDIS_REPLICA_PORT,
      connector: RailsFailover::Redis::Connector
    }.merge(opts))
  end
end
