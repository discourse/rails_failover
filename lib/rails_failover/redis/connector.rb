# frozen_string_literal: true

require_relative 'failover_handler'

module RailsFailover
  class Redis
    class Connector < ::Redis::Client::Connector
      def initialize(options)
        options[:original_driver] = options[:driver]

        options[:driver] = Class.new(options[:driver]) do
          def self.connect(options)
            super(options)
          rescue Timeout::Error,
                 SocketError,
                 Errno::EADDRNOTAVAIL,
                 Errno::ECONNREFUSED,
                 Errno::EHOSTDOWN,
                 Errno::EHOSTUNREACH,
                 Errno::ENETUNREACH,
                 Errno::ENOENT,
                 Errno::ETIMEDOUT,
                 Errno::EINVAL => e

            FailoverHandler.instance.verify_master(options.dup)
            raise e
          end
        end

        options.delete(:connector)
        @options = options.dup
        @replica_options = replica_options(options)
      end

      def resolve
        FailoverHandler.instance.master ? @options : @replica_options
      end

      def check(client)
        FailoverHandler.instance.register_client(client)
      end

      def on_disconnect(client)
        FailoverHandler.instance.deregister_client(client)
      end

      private

      def replica_options(options)
        opts = options.dup
        opts[:host] = opts.delete(:replica_host)
        opts[:port] = opts.delete(:replica_port)
        opts[:driver] = opts.delete(:original_driver)
        opts
      end
    end
  end
end
