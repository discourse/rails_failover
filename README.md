# RailsFailover

* Automatic failover and recovery for simple master-replica Redis setup

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rails_failover'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install rails_failover

## Usage

### ActiveRecord

In `config/application.rb` add `require 'rails_failover/active_record'` after `require "active_record/railtie"`.

In your database configuration, simply add `replica_host` and `replica_port` to your database configuration.

```
production:
  host: <primary db server host>
  port: <primary db server port>
  replica_host: <replica db server host>
  replica_port: <replica db server port>
```

The gem will automatically create an `ActiveRecord::ConnectionAdapters::ConnectionHandler` with the `ActiveRecord::Base.reading_role` as the `handler_key`.

#### Failover/Fallback Hooks

```
RailsFailover::ActiveRecord.on_failover do
  # Enable readonly mode
end

RailsFailover::ActiveRecord.on_fallback do
  # Disable readonly mode
end
```

#### Inter-process Communication for faster failover

When running multiple process on the same server, you may want to have all the processes failover as soon as one of the process detects that the primary database is down. If so, simply run `RailsFailover::ActiveRecord.after_fork` once you have forked a new process. For example:

```
# config/unicorn.conf.rb

after_fork do |server, worker|
  RailsFailover::ActiveRecord.after_fork
end
```

### Redis

```
Redis.new(host: "127.0.0.1", port: 6379, replica_host: "127.0.0.1", replica_port: 6380, connector: RailsFailover::Redis::Connector))
```

Callbacks can be registered when the master connection is down and when it is up.


```
RailsFailover::Redis.register_master_up_callback do
  # Switch site to read-only mode
end

RailsFailover::Redis.register_master_down_callback do
  # Switch site out of read-only mode
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### Testing

#### ActiveRecord

The ActiveRecord failover tests are run against a dummy Rails server. Run the following commands to run the test:

1. `make setup_pg`
1. `make start_pg`
1. `bin/rspec active_record`. You may also run the tests with more unicorn workers by adding the `UNICORN_WORKERS` env variable.

#### Redis

`bin/rspec redis`

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/discourse/rails_failover. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/discourse/rails_failover/blob/master/CODE_OF_CONDUCT.md).


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RailsFailover project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/discourse/rails_failover/blob/master/CODE_OF_CONDUCT.md).
