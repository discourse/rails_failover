include postgresql.mk
include redis.mk

all: redis

active_record: start_pg_primary create_test_database stop_pg test_active_record

test_active_record:
	@BUNDLE_GEMFILE=./spec/support/dummy_app/Gemfile bundle install --quiet
	@ACTIVE_RECORD=1 bundle exec rspec --tag type:active_record ${RSPEC_PATH}
