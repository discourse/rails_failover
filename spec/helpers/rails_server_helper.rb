# frozen_string_literal: true

module RailsServerHelper
  def setup_rails_server
    execute_command(
      "cd spec/support/dummy_app && BUNDLE_GEMFILE=Gemfile RAILS_ENV=production bin/bundle exec rails db:create db:migrate db:seed",
    )
  end

  def start_rails_server
    if (
         (unicorn_master_pid = get_unicorn_master_pid) != 0 &&
           (get_unicorn_worker_pids(unicorn_master_pid).size == 1)
       )
      return
    end

    system(
      "cd spec/support/dummy_app && BUNDLE_GEMFILE=Gemfile SECRET_KEY_BASE=somekey bin/bundle exec unicorn -c config/unicorn.conf.rb -D -E production",
    )

    count = 0
    timeout = 10

    while (unicorn_master_pid = get_unicorn_master_pid) == 0
      raise "Timeout while waiting for unicorn master to be up" if count == timeout
      count += 1
      sleep 1
    end

    count = 0
    timeout = 10

    while get_unicorn_worker_pids(unicorn_master_pid).size != 1
      raise "Timeout while waiting for unicorn worker to be up" if count == timeout
      count += 1
      sleep 1
    end

    true
  end

  def stop_rails_server
    system("kill -15 #{get_unicorn_master_pid}")

    count = 0
    timeout = 10

    while get_unicorn_master_pid != 0
      raise "Timeout while waiting for unicorn master to be down" if count == timeout
      count += 1
      sleep 1
    end

    true
  end

  def teardown_rails_server
    execute_command(
      "cd spec/support/dummy_app && BUNDLE_GEMFILE=Gemfile DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production bin/bundle exec rails db:drop",
    )
  end

  private

  def execute_command(command)
    output = `#{command}`
    raise "Command failed: #{command}\nOutput: #{output}" unless $?.success?

    puts output if ENV["VERBOSE"]

    output
  end

  def get_unicorn_master_pid
    execute_command(
      "ps aux | grep \"unicorn master\" | grep -v \"grep\" | awk '{print $2}'",
    ).strip.to_i
  end

  def get_unicorn_worker_pids(unicorn_master_pid)
    execute_command("pgrep -P #{unicorn_master_pid}").split("\n").map(&:to_i)
  end
end
