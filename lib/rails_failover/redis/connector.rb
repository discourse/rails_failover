# frozen_string_literal: true

require_relative 'handler'

module RailsFailover
  class Redis
    class Connector < ::Redis::Client::Connector
      def initialize(options)
        orignal_driver = options[:driver]

        options[:driver] = Class.new(options[:driver]) do
          def self.connect(options)
            is_failover_replica = (options[:host] == options[:replica_host]) &&
                                  (options[:port] == options[:replica_port])
            super(options).tap do |conn|
              conn.rails_failover_role = is_failover_replica ? REPLICA : PRIMARY
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

            Handler.instance.verify_primary(options) if !is_failover_replica
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
