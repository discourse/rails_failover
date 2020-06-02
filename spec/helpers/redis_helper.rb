# frozen_string_literal: true

module RedisHelper
  def create_redis_client(opts = {})
    Redis.new({
      host: "127.0.0.1",
      port: 6381,
      replica_host: "127.0.0.1",
      replica_port: 6382,
      connector: RailsFailover::Redis::Connector
    }.merge(opts))
  end
end
