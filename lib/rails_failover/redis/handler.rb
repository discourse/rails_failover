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
        @primaries_down = {}
        @clients = {}
        @ancestor_pid = Process.pid

        super() # Monitor#initialize
      end

      def verify_primary(options)
        mon_synchronize do
          primary_down(options)
          disconnect_clients(options)

          return if @thread&.alive?

          logger&.warn "Failover for Redis has been initiated"

          begin
            RailsFailover::Redis.on_failover_callback&.call
          rescue => e
            logger&.warn("RailsFailover::Redis.on_failover_callback failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}")
          end

          @thread = Thread.new do
            loop do
              thread = Thread.new { initiate_fallback_to_primary }
              thread.join

              if all_primaries_up
                logger&.warn "Fallback to primary for Redis has been completed."

                begin
                  RailsFailover::Redis.on_fallback_callback&.call
                rescue => e
                  logger&.warn("RailsFailover::Redis.on_fallback_callback failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}")
                end

                break
              end
            end
          end
        end
      end

      def initiate_fallback_to_primary
        frequency = RailsFailover::Redis.verify_primary_frequency_seconds
        sleep(frequency * ((rand(VERIFY_FREQUENCY_BUFFER_PRECENT) + 100) / 100.0))

        active_primaries_keys = {}

        primaries_down.each do |key, options|
          info = nil
          options = options.dup

          begin
            options[:driver] = options[:original_driver]
            primary_client = ::Redis::Client.new(options)
            logger&.debug "Checking connection to primary server (#{key})"
            info = primary_client.call([:info])
          rescue => e
            logger&.debug "Connection to primary server (#{key}) failed with '#{e.message}'"
          ensure
            primary_client&.disconnect
          end

          if info && info.include?(PRIMARY_LOADED_STATUS) && info.include?(PRIMARY_ROLE_STATUS)
            active_primaries_keys[key] = options
            logger&.debug "Primary server (#{key}) is active, disconnecting clients from replica"
          end
        end

        active_primaries_keys.each do |key, options|
          primary_up(options)
          disconnect_clients(options)
        end
      end

      def register_client(client)
        key = client.options[:id]

        mon_synchronize do
          clients[key] ||= []
          clients[key] << client
        end
      end

      def deregister_client(client)
        key = client.options[:id]

        mon_synchronize do
          if clients[key]
            clients[key].delete(client)

            if clients[key].empty?
              clients.delete(key)
            end
          end
        end
      end

      def primary_down?(options)
        mon_synchronize do
          primaries_down[options[:id]]
        end
      end

      private

      def all_primaries_up
        mon_synchronize { primaries_down.empty? }
      end

      def primary_up(options)
        mon_synchronize do
          primaries_down.delete(options[:id])
        end
      end

      def primary_down(options)
        mon_synchronize do
          primaries_down[options[:id]] = options.dup
        end
      end

      def clients
        process_pid = Process.pid
        return @clients[process_pid] if @clients[process_pid]

        mon_synchronize do
          if !@clients[process_pid]
            @clients[process_pid] = {}

            if process_pid != @ancestor_pid
              @clients.delete(@ancestor_pid)
            end
          end

          @clients[process_pid]
        end
      end

      def primaries_down
        process_pid = Process.pid
        return @primaries_down[process_pid] if @primaries_down[process_pid]

        mon_synchronize do
          if !@primaries_down[process_pid]
            @primaries_down[process_pid] = @primaries_down[@ancestor_pid] || {}

            if process_pid != @ancestor_pid
              @primaries_down.delete(@ancestor_pid)&.each do |id, options|
                verify_primary(options)
              end
            end
          end

          @primaries_down[process_pid]
        end
      end

      def disconnect_clients(options)
        key = options[:id]

        mon_synchronize do
          if clients[key]
            clients[key].dup.each do |c|
              c.disconnect
            end
          end
        end
      end

      def logger
        RailsFailover::Redis.logger
      end
    end
  end
end
