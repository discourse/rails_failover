# frozen_string_literal: true

require "redis"

# See https://github.com/redis/redis-rb/pull/908
class Redis::Client
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
