# frozen_string_literal: true

require "active_record"

require_relative "active_record/railtie" if defined?(::Rails)

require_relative "active_record/middleware"
require_relative "active_record/handler"

AR =
  (
    if ::ActiveRecord.respond_to?(:reading_role)
      ::ActiveRecord
    else
      ::ActiveRecord::Base
    end
  )

module RailsFailover
  module ActiveRecord
    def self.logger=(logger)
      @logger = logger
    end

    def self.logger
      @logger || Rails.logger
    end

    def self.verify_primary_frequency_seconds=(seconds)
      @verify_primary_frequency_seconds = seconds
    end

    def self.verify_primary_frequency_seconds
      @verify_primary_frequency_seconds || 5
    end

    def self.establish_reading_connection(handler, config)
      if config[:replica_host] && config[:replica_port]
        replica_config = config.dup
        replica_config[:host] = replica_config.delete(:replica_host)
        replica_config[:port] = replica_config.delete(:replica_port)
        replica_config[:replica] = true
        handler.establish_connection(replica_config)
      end
    end

    def self.register_force_reading_role_callback(&block)
      Middleware.force_reading_role_callback = block
    end

    def self.on_failover(&block)
      @on_failover_callback = block
    end

    def self.on_failover_callback!(key)
      @on_failover_callback&.call(key)
    rescue => e
      logger.warn(
        "RailsFailover::ActiveRecord.on_failover failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}",
      )
    end

    def self.on_fallback(&block)
      @on_fallback_callback = block
    end

    def self.on_fallback_callback!(key)
      @on_fallback_callback&.call(key)
    rescue => e
      logger.warn(
        "RailsFailover::ActiveRecord.on_fallback failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}",
      )
    end

    def self.reading_role
      AR.reading_role
    end

    def self.writing_role
      AR.writing_role
    end
  end
end
