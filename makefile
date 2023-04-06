include postgresql.mk
include redis.mk

all: redis

active_record: teardown_dummy_rails_server setup_dummy_rails_server test_active_record

test_active_record:
	@ACTIVE_RECORD=1 bundle exec rspec --tag type:active_record ${RSPEC_PATH}

setup_dummy_rails_server:
	@cd spec/support/dummy_app && bundle install --quiet && yarn install && RAILS_ENV=production $(BUNDLER_BIN) exec rails db:create db:migrate db:seed

start_dummy_rails_server:
	@cd spec/support/dummy_app && SECRET_KEY_BASE=somekey bundle exec unicorn -c config/unicorn.conf.rb -D -E production

stop_dummy_rails_server:
	@kill -TERM $(shell cat spec/support/dummy_app/tmp/pids/unicorn.pid)

teardown_dummy_rails_server:
	@cd spec/support/dummy_app && (! (bundle check > /dev/null 2>&1) || DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production $(BUNDLER_BIN) exec rails db:drop)
