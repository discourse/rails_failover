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
      SOFT_DISCONNECT_TIMEOUT_SECONDS = 1
      SOFT_DISCONNECT_POLL_SECONDS = 0.05

      def initialize
        @primaries_down = {}
        @clients = {}
        @ancestor_pid = Process.pid

        super() # Monitor#initialize
      end

      def verify_primary(options)
        mon_synchronize do
          primary_down(options)
          return if @thread&.alive?
          logger&.warn "Failover for Redis has been initiated"
          @thread = Thread.new { loop_until_all_up }
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

      def primaries_down_count
        mon_synchronize do
          primaries_down.count
        end
      end

      private

      def loop_until_all_up
        loop do
          ensure_primary_clients_disconnected
          try_fallback_to_primary

          if all_primaries_up
            logger&.warn "Fallback to primary for Redis has been completed."
            break
          end
        end
      end

      def try_fallback_to_primary
        frequency = RailsFailover::Redis.verify_primary_frequency_seconds
        sleep(frequency * ((rand(VERIFY_FREQUENCY_BUFFER_PRECENT) + 100) / 100.0))

        active_primaries_keys = {}

        mon_synchronize { primaries_down.dup }.each do |key, options|
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
          disconnect_clients(options, RailsFailover::Redis::REPLICA)
        end
      end

      def all_primaries_up
        mon_synchronize { primaries_down.empty? }
      end

      def primary_up(options)
        already_up = mon_synchronize do
          !primaries_down.delete(options[:id])
        end
        RailsFailover::Redis.on_fallback_callback!(options[:id]) if !already_up
      end

      def primary_down(options)
        already_down = false
        mon_synchronize do
          already_down = !!primaries_down[options[:id]]
          primaries_down[options[:id]] = options.dup
        end
        RailsFailover::Redis.on_failover_callback!(options[:id]) if !already_down
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

      def ensure_primary_clients_disconnected
        mon_synchronize { primaries_down.dup }.each do |key, options|
          disconnect_clients(options, RailsFailover::Redis::PRIMARY)
        end
      end

      def disconnect_clients(options, role)
        key = options[:id]

        matched_clients = mon_synchronize { clients[key].dup }
          &.filter { |c| c.connection.rails_failover_role == role }
          &.to_set

        return if matched_clients.nil? || matched_clients.empty?

        # This is not ideal, but the mutex we need is contained
        # in the ::Redis instance, not the Redis::Client
        ObjectSpace.each_object(::Redis) do |redis|
          # When subscribed, Redis#_client is not a Redis::Client
          # Instance variable is the only reliable way
          client = redis.instance_variable_get(:@original_client)
          next if !matched_clients.include?(client)
          soft_disconnect(redis, client, role)
        end
      end

      # Calling .disconnect can cause a running subscribe() to block forever
      # Therefore try to acquire the lock
      def soft_disconnect(redis, client, role)
        has_lock = redis.mon_try_enter

        if !has_lock
          begin
            client.connection.shutdown_socket
          rescue => e
            logger&.warn "Redis shutdown_socket for (#{role}) failed with #{e.class} '#{e.message}'"
          end

          waiting_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          loop do # Keep trying
            break if has_lock = redis.mon_try_enter
            break if !client.connection.connected? # Disconnected by other thread
            break if client.connection.rails_failover_role != role # Reconnected by other thread
            time_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if time_now > waiting_since + SOFT_DISCONNECT_TIMEOUT_SECONDS
            sleep SOFT_DISCONNECT_POLL_SECONDS
          end
        end

        client.disconnect if client.connection&.rails_failover_role == role
      ensure
        redis.mon_exit if has_lock
      end

      def logger
        RailsFailover::Redis.logger
      end
    end
  end
end
