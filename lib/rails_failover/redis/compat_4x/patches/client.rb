# frozen_string_literal: true

require "redis"
require "active_support/core_ext/module/delegation"

# See https://github.com/redis/redis-rb/pull/908
class Redis::Client
  delegate :rails_failover_role, :shutdown_socket, to: :connection, allow_nil: true

  def disconnect
    if connected?
      result = connection.disconnect
      @connector.on_disconnect(self)
      result
    end
  end
end

class Redis::Client::Connector
  def on_disconnect(client)
  end
end
