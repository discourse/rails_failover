# frozen_string_literal: true

require 'redis'

supported_version = '4'

if Gem::Version.new(Redis::VERSION) < Gem::Version.new(supported_version)
  raise "redis #{Redis::VERSION} is not supported. Please upgrade to Redis #{supported_version}."
end

require_relative "../redis/patches/client"
require_relative 'redis/connector'

module RailsFailover
  class Redis
    def self.after_fork
      Handler.instance.start_listener
    end

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
      @primary_down_callbacks ||= []
      @primary_down_callbacks.push(block)
    end

    def self.on_failover_callbacks
      @primary_down_callbacks || []
    end

    def self.on_fallback(&block)
      @primary_up_callbacks ||= []
      @primary_up_callbacks.push(block)
    end

    def self.on_fallback_callbacks
      @primary_up_callbacks || []
    end
  end
end
