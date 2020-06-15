# frozen_string_literal: true
require 'singleton'
require 'monitor'
require 'fileutils'

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
        mon_synchronize do
          primary_down(handler_key)
          return if @thread&.alive?

          logger.warn "Failover for ActiveRecord has been initiated"

          begin
            RailsFailover::ActiveRecord.on_failover_callback&.call
          rescue => e
            logger.warn("RailsFailover::ActiveRecord.on_failover_callback failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}")
          end

          @thread = Thread.new do
            loop do
              initiate_fallback_to_primary

              if all_primaries_up
                logger.warn "Fallback to primary for ActiveRecord has been completed."

                begin
                  RailsFailover::ActiveRecord.on_fallback_callback&.call
                rescue => e
                  logger.warn("RailsFailover::ActiveRecord.on_fallback_callback failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}")
                end

                break
              end
            end
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

      def primary_down?(handler_key)
        primaries_down[handler_key]
      end

      private

      def all_primaries_up
        mon_synchronize do
          primaries_down.empty?
        end
      end

      def primary_down(handler_key)
        mon_synchronize do
          primaries_down[handler_key] = true
        end
      end

      def primary_up(handler_key)
        mon_synchronize do
          primaries_down.delete(handler_key)
        end
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
