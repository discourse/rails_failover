# frozen_string_literal: true
require 'singleton'
require 'monitor'

module RailsFailover
  module ActiveRecord
    class Handler
      include Singleton
      include MonitorMixin

      VERIFY_FREQUENCY_BUFFER_PRECENT = 20

      def initialize
        @primaries_down = {}
        @ancestor_pid = Process.pid

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
        mon_synchronize do
          primaries_down.count
        end
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
        sleep(frequency * ((rand(VERIFY_FREQUENCY_BUFFER_PRECENT) + 100) / 100.0))

        active_handler_keys = []

        primaries_down.keys.each do |handler_key|
          connection_handler = ::ActiveRecord::Base.connection_handlers[handler_key]
          spec = connection_handler.retrieve_connection_pool(spec_name).spec
          config = spec.config
          logger.debug "#{Process.pid} Checking server for '#{handler_key} #{spec_name}'..."
          connection_active = false

          begin
            connection = ::ActiveRecord::Base.public_send(spec.adapter_method, config)
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

        active_handler_keys.each do |handler_key|
          primary_up(handler_key)
        end
      end

      def all_primaries_up
        mon_synchronize do
          primaries_down.empty?
        end
      end

      def primary_down(handler_key)
        already_down = false
        mon_synchronize do
          already_down = !!primaries_down[handler_key]
          primaries_down[handler_key] = true
        end
        RailsFailover::ActiveRecord.on_failover_callback!(handler_key) if !already_down
      end

      def primary_up(handler_key)
        already_up = mon_synchronize do
          !primaries_down.delete(handler_key)
        end
        RailsFailover::ActiveRecord.on_fallback_callback!(handler_key) if !already_up
      end

      def spec_name
        ::ActiveRecord::Base.connection_specification_name
      end

      def primaries_down
        process_pid = Process.pid
        return @primaries_down[process_pid] if @primaries_down[process_pid]

        mon_synchronize do
          if !@primaries_down[process_pid]
            @primaries_down[process_pid] = @primaries_down[@ancestor_pid] || {}

            if process_pid != @ancestor_pid
              @primaries_down.delete(@ancestor_pid)

              @primaries_down[process_pid].each_key do |handler_key|
                verify_primary(handler_key)
              end
            end
          end

          @primaries_down[process_pid]
        end
      end

      def logger
        ::Rails.logger
      end
    end
  end
end
