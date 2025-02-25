# RailsFailover

Automatic failover and recovery for primary/replica setup for:

1. Redis
2. ActiveRecord (PostgreSQL/MySQL Adapters)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rails_failover', require: false
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install rails_failover

## Usage

### ActiveRecord

In `config/application.rb` add `require 'rails_failover/active_record'` after `require "active_record/railtie"`.

In your database configuration, simply add `replica_host` and `replica_port` to your database configuration.

```yml
production:
  host: <primary db server host>
  port: <primary db server port>
  replica_host: <replica db server host>
  replica_port: <replica db server port>
```

The gem will automatically create a role (using `ActiveRecord.reading_role`) on
the default `ActiveRecord` connection handler.

#### Failover/Fallback Hooks

```ruby
RailsFailover::ActiveRecord.on_failover do
  # Enable readonly mode
end

RailsFailover::ActiveRecord.on_fallback do
  # Disable readonly mode
end
```

#### Multiple connection handlers

```yml
# config/database.yml

production:
  primary:
    host: <primary db server host>
    port: <primary db server port>
    replica_host: <replica db server host>
    replica_port: <replica db server port>
  second_database_writing:
    host: <primary db server host>
    port: <primary db server port>
    replica_host: <replica db server host>
    replica_port: <replica db server port>

# In your ActiveRecord base model or model.

connects_to database: { writing: :primary, second_database_writing: :second_database_writing }
```

### Redis

Add `require 'rails_failover/redis'` before creating a `Redis` instance.

```ruby
# Redis/RedisClient 4.x
Redis.new(
  host: "127.0.0.1",
  port: 6379,
  replica_host: "127.0.0.1",
  replica_port: 6380,
  connector: RailsFailover::Redis::Connector,
)

# Redis/RedisClient 5.x
Redis.new(
  host: "127.0.0.1",
  port: 6379,
  client_implementation: RailsFailover::Redis::Client,
  custom: {
    replica_host: "127.0.0.1",
    replica_port: 6380,
  }
)
```

Callbacks can be registered when the primary connection is down and when it is up.

```ruby
RailsFailover::Redis.on_failover_callback do
  # Switch site to read-only mode
end

RailsFailover::Redis.on_fallback_callback do
  # Switch site out of read-only mode
end
```

> ⚠️ If you’re using Sidekiq, don’t provide it with the replica configuration as it won’t work. RailsFailover works with a replica in read-only mode, meaning Sidekiq wouldn’t work properly anyway as it needs to write to Redis.

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### Testing

#### ActiveRecord

The ActiveRecord failover tests are run against a dummy Rails server. Run the following commands to run the test:

1. `make setup_pg`
3. `bin/rspec active_record`. You may also run the tests with more unicorn workers by adding the `UNICORN_WORKERS` env variable.

#### Redis

`bin/rspec redis`

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/discourse/rails_failover. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/discourse/rails_failover/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RailsFailover project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/discourse/rails_failover/blob/master/CODE_OF_CONDUCT.md).
