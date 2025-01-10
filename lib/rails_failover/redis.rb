# frozen_string_literal: true

require "redis"

supported_version = "4"

if Gem::Version.new(Redis::VERSION) < Gem::Version.new(supported_version)
  raise "redis #{Redis::VERSION} is not supported. Please upgrade to Redis #{supported_version}."
end

if Redis::VERSION >= "5"
  require_relative "redis/compat_5x/patches/client"
  require_relative "redis/compat_5x/config"
  require_relative "redis/compat_5x/client"
else
  require_relative "redis/compat_4x/patches/client"
  require_relative "redis/compat_4x/connector"
end

module RailsFailover
  class Redis
    PRIMARY = :primary
    REPLICA = :replica

    def self.logger=(logger)
      @logger = logger
    end

    def self.logger
      if @logger
        @logger
      elsif defined?(::Rails)
        ::Rails.logger
      end
    end

    def self.verify_primary_frequency_seconds=(seconds)
      @verify_primary_frequency_seconds = seconds
    end

    def self.verify_primary_frequency_seconds
      @verify_primary_frequency_seconds || 5
    end

    def self.on_failover(&block)
      @on_failover_callback = block
    end

    def self.on_failover_callback!(key)
      @on_failover_callback&.call(key)
    rescue => e
      logger.warn(
        "RailsFailover::Redis.on_failover failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}",
      )
    end

    def self.on_fallback(&block)
      @on_fallback_callback = block
    end

    def self.on_fallback_callback!(key)
      @on_fallback_callback&.call(key)
    rescue => e
      logger.warn(
        "RailsFailover::Redis.on_fallback failed: #{e.class} #{e.message}\n#{e.backtrace.join("\n")}",
      )
    end

    # For testing
    def self.clear_callbacks
      @on_fallback_callback = nil
      @on_failover_callback = nil
    end
  end
end
