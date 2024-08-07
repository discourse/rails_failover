# frozen_string_literal: true
require "singleton"
require "monitor"
require "concurrent"

module RailsFailover
  module ActiveRecord
    class Handler
      include Singleton
      include MonitorMixin

      VERIFY_FREQUENCY_BUFFER_PERCENT = 20

      def initialize
        @primaries_down = Concurrent::Map.new

        super() # Monitor#initialize
      end

      def verify_primary(handler_key)
        primary_down(handler_key)

        mon_synchronize do
          return if @thread&.alive?
          logger.warn "Failover for ActiveRecord has been initiated"
          @thread = Thread.new { loop_until_all_up }
        end
      end

      def primary_down?(handler_key)
        primaries_down[handler_key]
      end

      def primaries_down_count
        primaries_down.size
      end

      private

      def loop_until_all_up
        loop do
          initiate_fallback_to_primary

          if all_primaries_up
            logger.warn "Fallback to primary for ActiveRecord has been completed."
            break
          end
        end
      end

      def initiate_fallback_to_primary
        frequency = RailsFailover::ActiveRecord.verify_primary_frequency_seconds
        sleep(frequency * ((rand(VERIFY_FREQUENCY_BUFFER_PERCENT) + 100) / 100.0))

        active_handler_keys = []

        primaries_down.keys.each do |handler_key|
          logger.debug "#{Process.pid} Checking server for '#{handler_key} #{spec_name}'..."
          connection_active = false

          begin
            connection =
              ::ActiveRecord::Base
                .connection_handler
                .retrieve_connection(spec_name, role: handler_key)
                .tap(&:verify!)

            connection_active = connection.active?
          rescue => e
            logger.debug "#{Process.pid} Connection to server for '#{handler_key} #{spec_name}' failed with '#{e.message}'"
          ensure
            connection.disconnect! if connection
          end

          if connection_active
            logger.debug "#{Process.pid} Server for '#{handler_key} #{spec_name}' is active."
            active_handler_keys << handler_key
          end
        end

        active_handler_keys.each { |handler_key| primary_up(handler_key) }
      end

      def all_primaries_up
        primaries_down.empty?
      end

      def primary_down(handler_key)
        already_down = primaries_down.put_if_absent(handler_key, true)
        RailsFailover::ActiveRecord.on_failover_callback!(handler_key) if !already_down
      end

      def primary_up(handler_key)
        already_up = !primaries_down.delete(handler_key)
        RailsFailover::ActiveRecord.on_fallback_callback!(handler_key) if !already_up
      end

      def spec_name
        ::ActiveRecord::Base.connection_specification_name
      end

      def primaries_down
        ancestor_pids = nil
        value =
          @primaries_down.compute_if_absent(Process.pid) do
            ancestor_pids = @primaries_down.keys
            @primaries_down.values.first || Concurrent::Map.new
          end

        ancestor_pids&.each do |pid|
          @primaries_down.delete(pid)&.each_key { |key| verify_primary(key) }
        end

        value
      end

      def logger
        ::Rails.logger
      end
    end
  end
end
