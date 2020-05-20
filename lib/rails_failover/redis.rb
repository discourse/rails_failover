require_relative 'redis/connector'

module RailsFailover
  class Redis
    def self.logger=(logger)
      @logger = logger
    end

    def self.logger
      @logger
    end

    def self.verify_master_frequency_seconds=(seconds)
      @verify_master_frequency_seconds = seconds
    end

    def self.verify_master_frequency_seconds
      @verify_master_frequency_seconds || 5
    end

    def self.register_master_down_callback(&block)
      @master_down_callbacks ||= []
      @master_down_callbacks.push(block)
    end

    def self.master_down_callbacks
      @master_down_callbacks || []
    end

    def self.register_master_up_callback(&block)
      @master_up_callbacks ||= []
      @master_up_callbacks.push(block)
    end

    def self.master_up_callbacks
      @master_up_callbacks || []
    end
  end
end
