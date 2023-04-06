# frozen_string_literal: true

require "bundler/setup"
require "byebug"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  if ENV["REDIS"]
    require "rails_failover/redis"
    require "helpers/redis_helper"
    config.include RedisHelper

    puts "Redis #{Redis::VERSION}"
  end

  if ENV["ACTIVE_RECORD"]
    require "helpers/url_helper"
    config.include UrlHelper

    puts "ActiveRecord #{ActiveRecord::VERSION::STRING}"
  end
end
