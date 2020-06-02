# frozen_string_literal: true

require 'monitor'
require 'singleton'

module RailsFailover
  class Redis
    class Handler
      include Singleton
      include MonitorMixin

      PRIMARY_ROLE_STATUS = "role:master"
      PRIMARY_LOADED_STATUS = "loading:0"
      VERIFY_FREQUENCY_BUFFER_PRECENT = 20

      def initialize
        @primary = true
        @clients = []

        super() # Monitor#initialize
      end

      def verify_primary(options)
        mon_synchronize do
          return if @thread&.alive?

          self.primary = false
          disconnect_clients
          RailsFailover::Redis.primary_down_callbacks.each { |callback| callback.call }
          logger&.warn "Failover for Redis has been initiated"

          @thread = Thread.new do
            loop do
              thread = Thread.new { initiate_fallback_to_primary(options) }
              thread.join

              if self.primary
                logger&.warn "Fallback to primary for Redis has been completed."
                RailsFailover::Redis.primary_up_callbacks.each { |callback| callback.call }
                break
              end
            ensure
              thread.kill
            end
          end
        end
      end

      def initiate_fallback_to_primary(options)
        frequency = RailsFailover::Redis.verify_primary_frequency_seconds
        sleep(frequency * ((rand(VERIFY_FREQUENCY_BUFFER_PRECENT) + 100) / 100.0))

        info = nil

        begin
          primary_client = ::Redis::Client.new(options.dup)
          logger&.debug "Checking connection to primary server..."
          info = primary_client.call([:info])
        rescue => e
          logger&.debug "Connection to primary server failed with '#{e.message}'"
        ensure
          primary_client&.disconnect
        end

        if info && info.include?(PRIMARY_LOADED_STATUS) && info.include?(PRIMARY_ROLE_STATUS)
          self.primary = true
          logger&.debug "Primary server is active, disconnecting clients from replica"
          disconnect_clients
        end
      end

      def register_client(client)
        mon_synchronize do
          @clients << client
        end
      end

      def deregister_client(client)
        mon_synchronize do
          @clients.delete(client)
        end
      end

      def clients
        mon_synchronize { @clients }
      end

      def primary
        mon_synchronize { @primary }
      end

      def primary=(args)
        mon_synchronize { @primary = args }
      end

      private

      def disconnect_clients
        mon_synchronize do
          @clients.dup.each do |c|
            c.disconnect
          end
        end
      end

      def logger
        RailsFailover::Redis.logger
      end
    end
  end
end
