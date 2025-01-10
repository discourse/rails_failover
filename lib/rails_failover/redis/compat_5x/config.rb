# frozen_string_literal: true

require "delegate"
require_relative "handler"

module RailsFailover
  class Redis
    class Config < SimpleDelegator
      attr_reader :driver, :primary_host, :primary_port, :id
      attr_accessor :rails_failover_role

      def initialize(object)
        super
        @primary_host = object.host
        @primary_port = object.port
        @id ||= "#{object.host}:#{object.port}"
        @driver =
          Class.new(object.driver) do
            def connect
              is_primary =
                (config.host == config.primary_host) && (config.port == config.primary_port)
              super.tap { config.rails_failover_role = is_primary ? PRIMARY : REPLICA }
            rescue ::Redis::TimeoutError,
                   RedisClient::CannotConnectError,
                   SocketError,
                   Errno::EADDRNOTAVAIL,
                   Errno::ECONNREFUSED,
                   Errno::EHOSTDOWN,
                   Errno::EHOSTUNREACH,
                   Errno::ENETUNREACH,
                   Errno::ENOENT,
                   Errno::ETIMEDOUT,
                   Errno::EINVAL => e
              Handler.instance.verify_primary(config) if is_primary
              raise e
            end
          end
      end

      def host
        return super unless Handler.instance.primary_down?(id)
        custom[:replica_host]
      end

      def port
        return super unless Handler.instance.primary_down?(id)
        custom[:replica_port]
      end

      def new_primary_client
        ::Redis::Client.new(__getobj__)
      end

      def [](key)
        instance_variable_get("@#{key}")
      end
    end
  end
end
