# frozen_string_literal: true

require 'active_record'
require_relative 'active_record/railtie'
require_relative 'active_record/middleware'
require_relative 'active_record/handler'

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

    def self.establish_reading_connection(connection_spec)
      config = connection_spec.config

      if config[:replica_host] && config[:replica_port]
        replica_config = config.dup

        replica_config[:host] = replica_config.delete(:replica_host)
        replica_config[:port] = replica_config.delete(:replica_port)
        replica_config[:replica] = true

        handler = ::ActiveRecord::Base.connection_handlers[::ActiveRecord::Base.reading_role]
        handler.establish_connection(replica_config)
      end
    end
  end
end
