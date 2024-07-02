# frozen_string_literal: true

module PostgresHelper
  def start_pg_primary
    return if pg_primary_is_up?
    system("make start_pg_primary")
    wait_for_pg_primary_to_be_up
  end

  def stop_pg_primary
    return if pg_primary_is_down?
    system("make stop_pg_primary")
    wait_for_pg_primary_to_be_down
  end

  def start_pg_replica
    system("make start_pg_replica")
    wait_for_pg_replica_to_be_up
  end

  def stop_pg_replica
    system("make stop_pg_replica")
    wait_for_pg_replica_to_be_down
  end

  private

  def pg_primary_is_up?
    File.exist?(pg_primary_pid_path)
  end

  def pg_primary_is_down?
    !File.exist?(pg_primary_pid_path)
  end

  def wait_for_pg_primary_to_be_up
    wait_for_pg_to_be_up(role: :primary)
  end

  def wait_for_pg_primary_to_be_down
    wait_for_pg_to_be_down(role: :primary)
  end

  def wait_for_pg_replica_to_be_up
    wait_for_pg_to_be_up(role: :replica)
  end

  def wait_for_pg_replica_to_be_down
    wait_for_pg_to_be_down(role: :replica)
  end

  def wait_for_pg_to_be_up(role:)
    wait_for(timeout: 5) { File.exist?(self.send("pg_#{role}_pid_path")) }
  end

  def wait_for_pg_to_be_down(role:)
    wait_for(timeout: 5) { !File.exist?(self.send("pg_#{role}_pid_path")) }
  end

  def pg_replica_pid_path
    "#{gem_root}/tmp/replica/data/postmaster.pid"
  end

  def pg_primary_pid_path
    "#{gem_root}/tmp/primary/data/postmaster.pid"
  end

  def gem_root
    File.expand_path("../..", __dir__)
  end
end
