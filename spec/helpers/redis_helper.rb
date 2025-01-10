# frozen_string_literal: true

require "active_support/core_ext/hash/deep_merge"

module RedisHelper
  REDIS_PRIMARY_PORT = 6381
  REDIS_REPLICA_PORT = 6382
  def create_redis_client(opts = {})
    base_opts =
      if Redis::VERSION >= "5"
        {
          host: "127.0.0.1",
          port: REDIS_PRIMARY_PORT,
          client_implementation: RailsFailover::Redis::Client,
          custom: {
            replica_host: "127.0.0.1",
            replica_port: REDIS_REPLICA_PORT,
          },
        }
      else
        {
          host: "127.0.0.1",
          port: REDIS_PRIMARY_PORT,
          connector: RailsFailover::Redis::Connector,
          replica_host: "127.0.0.1",
          replica_port: REDIS_REPLICA_PORT,
        }
      end
    Redis.new(base_opts.deep_merge(opts))
  end
end
