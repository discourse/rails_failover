worker_processes ENV["UNICORN_WORKERS"].to_i || 5

path = File.expand_path(File.expand_path(File.dirname(__FILE__)) + "/../")

working_directory path

listen 8080

# nuke workers after 30 seconds instead of 60 seconds (the default)
timeout 30

stderr_path "#{path}/log/unicorn.stderr.log"
stdout_path "#{path}/log/unicorn.stdout.log"
pid "#{path}/tmp/pids/unicorn.pid"

# combine Ruby 2.0.0+ with "preload_app true" for memory savings
preload_app true

before_fork do |server, worker|
  # Throttle the master from forking too quickly by sleeping.  Due
  # to the implementation of standard Unix signal handlers, this
  # helps (but does not completely) prevent identical, repeated signals
  # from being lost when the receiving process is busy.
  sleep 1
end

after_fork do |server, worker|
  RailsFailover::ActiveRecord.after_fork
end
