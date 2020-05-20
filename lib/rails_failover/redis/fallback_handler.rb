# frozen_string_literal: true
require 'monitor'
require 'singleton'

module RailsFailover
  class Redis
    class FallbackHandler
      include Singleton
      include MonitorMixin

      MASTER_ROLE_STATUS = "role:master"
      MASTER_LOADED_STATUS = "loading:0"

      def initialize
        @master = true
        @clients = []

        super() # Monitor#initialize
      end

      def verify_master(options)
        mon_synchronize do
          return if @thread&.alive?

          RailsFailover::Redis.master_down_callbacks.each { |callback| callback.call }

          @thread = Thread.new do
            loop do
              thread = Thread.new { initiate_fallback_to_master(options) }
              thread.join
              break if mon_synchronize { @master }
              sleep (RailsFailover::Redis.verify_master_frequency_seconds + (Time.now.to_i % RailsFailover::Redis.verify_master_frequency_seconds))
            ensure
              thread.kill
            end
          end
        end
      end

      def initiate_fallback_to_master(options)
        info = nil

        begin
          master_client = ::Redis::Client.new(options.dup)
          log "#{log_prefix}: Checking connection to master server..."
          info = master_client.call([:info])
        rescue => e
          log "#{log_prefix}: Connection to Master server failed with '#{e.message}'"
        ensure
          master_client&.disconnect
        end

        if info && info.include?(MASTER_LOADED_STATUS) && info.include?(MASTER_ROLE_STATUS)
          self.master = true
          log "#{log_prefix}: Master server is active, disconnecting clients from replica"
          disconnect_clients
          RailsFailover::Redis.master_up_callbacks.each { |callback| callback.call }
        end
      end

      def register_client(client)
        mon_synchronize do
          @clients << client
        end
      end

      def master
        mon_synchronize { @master }
      end

      def master=(args)
        mon_synchronize { @master = args }
      end

      private

      def disconnect_clients
        mon_synchronize do
          @clients.each(&:disconnect)
          @clients.clear
        end
      end

      def log(message)
        if logger = RailsFailover::Redis.logger
          logger.warn(message)
        end
      end

      def log_prefix
        "#{self.class}"
      end
    end
  end
end
