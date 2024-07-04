PG_BIN_DIR               := $(shell pg_config --bindir)
PWD                      := $(shell pwd)
PG_PRIMARY_DIR           := /tmp/primary
PG_PRIMARY_DATA_DIR      := $(PG_PRIMARY_DIR)/data
PG_PRIMARY_RUN_DIR       := $(PG_PRIMARY_DIR)/run
PG_REPLICA_DIR           := /tmp/replica
PG_REPLICA_DATA_DIR      := $(PG_REPLICA_DIR)/data
PG_REPLICA_RUN_DIR       := $(PG_REPLICA_DIR)/run
PG_PRIMARY_PORT          := 5434
PG_REPLICA_PORT          := 5435
PG_REPLICATION_USER      := replication
PG_REPLICATION_PASSWORD  := password
PG_REPLICATION_SLOT_NAME := replication

setup_pg: init_primary start_pg_primary setup_primary init_replica stop_pg_primary

create_test_database:
	@$(PG_BIN_DIR)/psql -p $(PG_PRIMARY_PORT) -h $(PG_PRIMARY_RUN_DIR) -d postgres --quiet -c "DROP DATABASE IF EXISTS test;"
	@$(PG_BIN_DIR)/psql -p $(PG_PRIMARY_PORT) -h $(PG_PRIMARY_RUN_DIR) -d postgres --quiet -c "CREATE DATABASE test;"

setup_primary:
	@$(PG_BIN_DIR)/psql -p $(PG_PRIMARY_PORT) -h $(PG_PRIMARY_RUN_DIR) -d postgres -c "CREATE USER $(PG_REPLICATION_USER) WITH REPLICATION ENCRYPTED PASSWORD '$(PG_REPLICATION_PASSWORD)';"
	@$(PG_BIN_DIR)/psql -p $(PG_PRIMARY_PORT) -h $(PG_PRIMARY_RUN_DIR) -d postgres -c "SELECT * FROM pg_create_physical_replication_slot('$(PG_REPLICATION_SLOT_NAME)');"
	@$(PG_BIN_DIR)/psql -p $(PG_PRIMARY_PORT) -h $(PG_PRIMARY_RUN_DIR) -d postgres -c "CREATE USER test;"

start_pg: start_pg_primary start_pg_replica

stop_pg: stop_pg_replica stop_pg_primary

init_primary:
	@mkdir -p $(PG_PRIMARY_DATA_DIR)
	@mkdir -p $(PG_PRIMARY_RUN_DIR)
	@$(PG_BIN_DIR)/initdb -E UTF8 -D $(PG_PRIMARY_DATA_DIR)

init_replica:
	@mkdir -p $(PG_REPLICA_DATA_DIR)
	@mkdir -p $(PG_REPLICA_RUN_DIR)
	@PGPASSWORD=$(PG_REPLICATION_PASSWORD) $(PG_BIN_DIR)/pg_basebackup -D $(PG_REPLICA_DATA_DIR) -X stream -h $(PG_PRIMARY_RUN_DIR) -p $(PG_PRIMARY_PORT) -U $(PG_REPLICATION_USER) -w -R
	@chmod 0700 $(PG_REPLICA_DATA_DIR)

start_pg_primary:
	@if [ ! -d "$(PG_PRIMARY_DATA_DIR)" ] || ! $(PG_BIN_DIR)/pg_ctl status -D $(PG_PRIMARY_DATA_DIR) > /dev/null 2>&1; then \
		$(PG_BIN_DIR)/pg_ctl --silent --log /dev/null -w -D $(PG_PRIMARY_DATA_DIR) -o "-p $(PG_PRIMARY_PORT)" -o "-k $(PG_PRIMARY_RUN_DIR)" start; \
		while ! $(PG_BIN_DIR)/pg_ctl status -D $(PG_PRIMARY_DATA_DIR) > /dev/null 2>&1; do \
			sleep 1; \
		done; \
	fi

start_pg_replica:
	@if [ ! -d "$(PG_REPLICA_DATA_DIR)" ] || ! $(PG_BIN_DIR)/pg_ctl status -D $(PG_REPLICA_DATA_DIR) > /dev/null 2>&1; then \
		$(PG_BIN_DIR)/pg_ctl --silent --log /dev/null -w -D $(PG_REPLICA_DATA_DIR) -o "-p $(PG_REPLICA_PORT)" -o "-k $(PG_REPLICA_RUN_DIR)" start; \
		while ! $(PG_BIN_DIR)/pg_ctl status -D $(PG_REPLICA_DATA_DIR) > /dev/null 2>&1; do \
			sleep 1; \
		done; \
	fi

stop_pg_primary:
	@if [ -d "$(PG_PRIMARY_DATA_DIR)" ] && $(PG_BIN_DIR)/pg_ctl status -D $(PG_PRIMARY_DATA_DIR) > /dev/null 2>&1; then \
		$(PG_BIN_DIR)/pg_ctl --silent --log /dev/null -w -D $(PG_PRIMARY_DATA_DIR) -o "-p $(PG_PRIMARY_PORT)" -o "-k $(PG_PRIMARY_RUN_DIR)" stop; \
		while $(PG_BIN_DIR)/pg_ctl status -D $(PG_PRIMARY_DATA_DIR) > /dev/null 2>&1; do \
			sleep 1; \
		done; \
	fi

stop_pg_replica:
	@if [ -d "$(PG_REPLICA_DATA_DIR)" ] && $(PG_BIN_DIR)/pg_ctl status -D $(PG_REPLICA_DATA_DIR) > /dev/null 2>&1; then \
		$(PG_BIN_DIR)/pg_ctl --silent --log /dev/null -w -D $(PG_REPLICA_DATA_DIR) -o "-p $(PG_REPLICA_PORT)" -o "-k $(PG_REPLICA_RUN_DIR)" stop; \
		while $(PG_BIN_DIR)/pg_ctl status -D $(PG_REPLICA_DATA_DIR) > /dev/null 2>&1; do \
			sleep 1; \
		done; \
	fi

cleanup_pg:
	@rm -rf $(PG_PRIMARY_DIR) $(PG_REPLICA_DIR)
