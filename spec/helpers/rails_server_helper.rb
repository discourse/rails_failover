# frozen_string_literal: true

module RailsServerHelper
  TIMEOUT = 30

  def setup_rails_server
    execute_command(
      "cd spec/support/dummy_app && BUNDLE_GEMFILE=Gemfile RAILS_ENV=production bin/rails db:migrate db:seed",
    )
  end

  def start_rails_server
    if (
         (unicorn_master_pid = get_unicorn_master_pid) != 0 &&
           (get_unicorn_worker_pids(unicorn_master_pid).size == 1.to_i)
       )
      return
    end

    system(
      "cd spec/support/dummy_app && BUNDLE_GEMFILE=Gemfile SECRET_KEY_BASE=somekey bin/bundle exec unicorn -c config/unicorn.conf.rb -D -E production",
    )

    wait_for(
      timeout: TIMEOUT,
      sleep_duration: 1,
      message: "Timeout while waiting for unicorn master to be up",
    ) { get_unicorn_master_pid != 0 }

    wait_for(
      timeout: TIMEOUT,
      sleep_duration: 1,
      message: "Timeout while waiting for unicorn worker to be up",
    ) { get_unicorn_worker_pids(get_unicorn_master_pid).size == 1 }

    true
  end

  def stop_rails_server
    system("kill -s QUIT #{get_unicorn_master_pid}")

    wait_for(
      timeout: TIMEOUT,
      sleep_duration: 1,
      message: "Timeout while waiting for unicorn master to be down",
    ) { get_unicorn_master_pid == 0 }

    true
  end

  private

  def execute_command(command)
    output = `#{command}`
    raise "Command failed: #{command}\nOutput: #{output}" unless $?.success?
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
