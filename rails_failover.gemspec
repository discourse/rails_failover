# frozen_string_literal: true

require_relative 'lib/rails_failover/version'

Gem::Specification.new do |spec|
  spec.name          = "rails_failover"
  spec.version       = RailsFailover::VERSION
  spec.authors       = ["Alan Tan"]
  spec.email         = ["tgx@discourse.org"]

  spec.summary       = %q{Failover for ActiveRecord and Redis}
  spec.homepage      = "https://github.com/discourse/rails_failover"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", "~> 6.0"
  spec.add_dependency "railties", "~> 6.0"

  spec.add_dependency "concurrent-ruby"
end
