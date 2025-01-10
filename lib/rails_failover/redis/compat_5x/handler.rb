# frozen_string_literal: true

require_relative "../handler_base"

module RailsFailover
  class Redis
    class Handler < HandlerBase
      def new_primary_client(config)
        config.new_primary_client
      end

      def primary_client_info(client)
        client.call_v([:info])
      end

      def soft_disconnect_original_client(matched_clients, redis, role)
        return if !matched_clients.include?(redis._client)
        soft_disconnect(redis, redis._client, role)
      end
    end
  end
end
