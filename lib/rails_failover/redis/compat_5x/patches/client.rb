# frozen_string_literal: true

require "redis"
require "active_support/core_ext/module/delegation"

class Redis::Client
  delegate :rails_failover_role, to: :config, allow_nil: true

  alias shutdown_socket close

  def disconnect
    close
    on_disconnect
    self
  end

  def on_disconnect
  end
end

class Redis::SubscribedClient
  delegate :connected?, to: :@client
end

class RedisClient::PubSub
  delegate :connected?, to: :@raw_connection, allow_nil: true
end
