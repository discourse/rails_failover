# frozen_string_literal: true

require "monitor"
require "singleton"
require "concurrent"

module RailsFailover
  class Redis
    class HandlerBase
      include Singleton
      include MonitorMixin

      PRIMARY_ROLE_STATUS = "role:master"
      PRIMARY_LOADED_STATUS = "loading:0"
      VERIFY_FREQUENCY_BUFFER_PERCENT = 20
      SOFT_DISCONNECT_TIMEOUT_SECONDS = 1
      SOFT_DISCONNECT_POLL_SECONDS = 0.05

      def initialize
        @primaries_down = Concurrent::Map.new
        @clients = Concurrent::Map.new

        super() # Monitor#initialize
      end

      def verify_primary(config)
        primary_down(config)

        mon_synchronize do
          return if @thread&.alive?
          logger&.warn "Failover for Redis has been initiated"
          @thread = Thread.new { loop_until_all_up }
        end
      end

      def register_client(client, id)
        clients_for_id(id).put_if_absent(client, true)
      end

      def deregister_client(client, id)
        clients_for_id(id).delete(client)
      end

      def primary_down?(id)
        primaries_down[id]
      end

      def primaries_down_count
        primaries_down.size
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
        sleep(frequency * ((rand(VERIFY_FREQUENCY_BUFFER_PERCENT) + 100) / 100.0))

        active_primaries_keys = {}

        primaries_down.each do |key, config|
          info = nil
          config = config.dup

          begin
            primary_client = new_primary_client(config)
            logger&.debug "Checking connection to primary server (#{key})"
            info = primary_client_info(primary_client)
          rescue => e
            logger&.debug "Connection to primary server (#{key}) failed with '#{e.message}'"
          ensure
            primary_client&.disconnect
          end

          if info && info.include?(PRIMARY_LOADED_STATUS) && info.include?(PRIMARY_ROLE_STATUS)
            active_primaries_keys[key] = config
            logger&.debug "Primary server (#{key}) is active, disconnecting clients from replica"
          end
        end

        active_primaries_keys.each do |key, config|
          primary_up(config)
          disconnect_clients(config[:id], RailsFailover::Redis::REPLICA)
        end
      end

      def all_primaries_up
        primaries_down.empty?
      end

      def primary_up(config)
        already_up = !primaries_down.delete(config[:id])
        RailsFailover::Redis.on_fallback_callback!(config[:id]) if !already_up
      end

      def primary_down(config)
        already_down = primaries_down.put_if_absent(config[:id], config.dup)
        RailsFailover::Redis.on_failover_callback!(config[:id]) if !already_down
      end

      def primaries_down
        ancestor_pids = nil
        value =
          @primaries_down.compute_if_absent(Process.pid) do
            ancestor_pids = @primaries_down.keys
            @primaries_down.values.first || Concurrent::Map.new
          end

        ancestor_pids&.each do |pid|
          @primaries_down.delete(pid)&.each { |id, config| verify_primary(config) }
        end

        value
      end

      def clients_for_id(id)
        clients.compute_if_absent(id) { Concurrent::Map.new }
      end

      def clients
        ancestor_pids = nil
        clients_for_pid =
          @clients.compute_if_absent(Process.pid) do
            ancestor_pids = @clients.keys
            Concurrent::Map.new
          end
        ancestor_pids&.each { |k| @clients.delete(k) }
        clients_for_pid
      end

      def ensure_primary_clients_disconnected
        primaries_down.each do |key, config|
          disconnect_clients(config[:id], RailsFailover::Redis::PRIMARY)
        end
      end

      def disconnect_clients(id, role)
        matched_clients =
          clients_for_id(id)&.keys&.select { _1.rails_failover_role == role }&.to_set

        return if matched_clients.nil? || matched_clients.empty?

        # This is not ideal, but the mutex we need is contained
        # in the ::Redis instance, not the Redis::Client
        ObjectSpace.each_object(::Redis) do |redis|
          soft_disconnect_original_client(matched_clients, redis, role)
        end
      end

      # Calling .disconnect can cause a running subscribe() to block forever
      # Therefore try to acquire the lock
      def soft_disconnect(redis, client, role)
        has_lock = redis_mon_try_enter(redis)

        if !has_lock
          begin
            client.shutdown_socket
          rescue => e
            logger&.warn "Redis shutdown_socket for (#{role}) failed with #{e.class} '#{e.message}'"
          end

          waiting_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          loop do # Keep trying
            break if has_lock = redis_mon_try_enter(redis)
            break if !client.connected? # Disconnected by other thread
            break if client.rails_failover_role != role # Reconnected by other thread
            time_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if time_now > waiting_since + SOFT_DISCONNECT_TIMEOUT_SECONDS
            sleep SOFT_DISCONNECT_POLL_SECONDS
          end
        end
        client.disconnect if client.rails_failover_role == role
      ensure
        redis_mon_exit(redis) if has_lock
      end

      def logger
        RailsFailover::Redis.logger
      end

      def redis_mon_try_enter(redis)
        if redis.respond_to? :mon_try_enter
          redis.mon_try_enter
        else
          redis.instance_variable_get(:@monitor).mon_try_enter
        end
      end

      def redis_mon_exit(redis)
        if redis.respond_to? :mon_exit
          redis.mon_exit
        else
          redis.instance_variable_get(:@monitor).mon_exit
        end
      end
    end
  end
end
