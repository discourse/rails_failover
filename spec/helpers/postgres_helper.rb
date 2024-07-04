# frozen_string_literal: true

module PostgresHelper
  def start_pg_primary
    system("make start_pg_primary")
  end

  def stop_pg_primary
    system("make stop_pg_primary")
  end

  def start_pg_replica
    system("make start_pg_replica")
  end

  def stop_pg_replica
    system("make stop_pg_replica")
  end
end
