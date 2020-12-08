# frozen_string_literal: true

require_relative 'handler'

module RailsFailover
  class Redis
    class Connector < ::Redis::Client::Connector
      def initialize(options)
        orignal_driver = options[:driver]
        options[:primary_host] = options[:host]
        options[:primary_port] = options[:port]

        options[:driver] = Class.new(options[:driver]) do
          def self.connect(options)
            is_primary = (options[:host] == options[:primary_host]) &&
                         (options[:port] == options[:primary_port])
            super(options).tap do |conn|
              conn.rails_failover_role = is_primary ? PRIMARY : REPLICA
            end
          rescue ::Redis::TimeoutError,
                 SocketError,
                 Errno::EADDRNOTAVAIL,
                 Errno::ECONNREFUSED,
                 Errno::EHOSTDOWN,
                 Errno::EHOSTUNREACH,
                 Errno::ENETUNREACH,
                 Errno::ENOENT,
                 Errno::ETIMEDOUT,
                 Errno::EINVAL => e

            Handler.instance.verify_primary(options) if is_primary
            raise e
          end

          attr_accessor :rails_failover_role

          def shutdown_socket
            @sock&.shutdown
          rescue Errno::ENOTCONN
          end
        end

        options[:original_driver] = orignal_driver
        options.delete(:connector)
        options[:id] ||= "#{options[:host]}:#{options[:port]}"
        @replica_options = replica_options(options)
        @options = options.dup
      end

      def resolve
        if Handler.instance.primary_down?(@options)
          @replica_options
        else
          @options
        end
      end

      def check(client)
        Handler.instance.register_client(client)
        expected_role = Handler.instance.primary_down?(@options) ? REPLICA : PRIMARY
        if client.connection.rails_failover_role != expected_role
          raise ::Redis::CannotConnectError, "Opened with unexpected failover role"
        end
      end

      def on_disconnect(client)
        Handler.instance.deregister_client(client)
      end

      private

      def replica_options(options)
        opts = options.dup
        opts[:host] = opts[:replica_host]
        opts[:port] = opts[:replica_port]
        opts
      end
    end
  end
end
