# frozen_string_literal: true

require_relative "../handler_base"

module RailsFailover
  class Redis
    class Handler < HandlerBase
      def new_primary_client(options)
        options[:driver] = options[:original_driver]
        ::Redis::Client.new(options)
      end

      def primary_client_info(client)
        client.call([:info])
      end

      def soft_disconnect_original_client(matched_clients, redis, role)
        # When subscribed, Redis#_client is not a Redis::Client
        # Instance variable is the only reliable way
        client = redis.instance_variable_get(:@original_client)
        return if !matched_clients.include?(client)
        soft_disconnect(redis, client, role)
      end
    end
  end
end
