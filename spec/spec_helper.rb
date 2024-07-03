# frozen_string_literal: true

require "bundler/setup"
require "byebug"
require "helpers/generic_helper"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include GenericHelper

  if ENV["REDIS"]
    require "rails_failover/redis"
    require "helpers/redis_helper"
    config.include RedisHelper
  end

  if ENV["ACTIVE_RECORD"]
    require "helpers/url_helper"
    require "helpers/postgres_helper"
    require "helpers/rails_server_helper"
    config.include UrlHelper
    config.include PostgresHelper
    config.include RailsServerHelper
  end
end
