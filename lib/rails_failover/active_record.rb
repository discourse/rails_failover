# frozen_string_literal: true

require "active_record"

require_relative "active_record/railtie" if defined?(::Rails)

require_relative "active_record/middleware"
require_relative "active_record/handler"

module RailsFailover
  module ActiveRecord
    class << self
      def config
        ::ActiveRecord::Base.connection_db_config.configuration_hash
      end

      def logger=(logger)
        @logger = logger
      end

      def logger
        @logger || Rails.logger
      end

      def verify_primary_frequency_seconds=(seconds)
        @verify_primary_frequency_seconds = seconds
      end

      def verify_primary_frequency_seconds
        @verify_primary_frequency_seconds || 5
      end

      def establish_reading_connection(handler, config, role: reading_role)
        return unless config[:replica_host] && config[:replica_port]
        replica_config = config.dup
        replica_config[:host] = replica_config.delete(:replica_host)
        replica_config[:port] = replica_config.delete(:replica_port)
        replica_config[:replica] = true
        handler.establish_connection(replica_config, role: role)
      end

      def register_force_reading_role_callback(&block)
        Middleware.force_reading_role_callback = block
      end

      def on_failover(&block)
        @on_failover_callback = block
      end

      def on_failover_callback!(key)
        @on_failover_callback&.call(key)
      rescue => e
        logger.warn(
          "RailsFailover::ActiveRecord.on_failover failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}",
        )
      end

      def on_fallback(&block)
        @on_fallback_callback = block
      end

      def on_fallback_callback!(key)
        @on_fallback_callback&.call(key)
      rescue => e
        logger.warn(
          "RailsFailover::ActiveRecord.on_fallback failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}",
        )
      end

      def reading_role
        ::ActiveRecord.try(:reading_role) || ::ActiveRecord::Base.reading_role
      end

      def writing_role
        ::ActiveRecord.try(:writing_role) || ::ActiveRecord::Base.writing_role
      end
    end
  end
end
