# frozen_string_literal: true
source "https://rubygems.org"

# Specify your gem's dependencies in rails_failover.gemspec
gemspec

gem "rake", "~> 12.0"
gem "rspec", "~> 3.0"

group :development do
  gem 'rubocop-discourse'
end

group :development, :test do
  gem 'byebug'
  gem 'redis', '~> 4.1'
  gem 'pg', '~> 1.2'
  gem 'activerecord', '~> 6.0'
  gem 'rack'
end
