# frozen_string_literal: true

require 'spec_helper'
require 'pg'
require 'rack'
require 'rails_failover/active_record'

RSpec.describe RailsFailover::ActiveRecord::Middleware, type: :active_record do
  let(:app) { ->(env) { [200, env, "app"] } }

  describe '.force_reading_role_callback' do
    it 'should be able to force the reading role via a callback' do
      middleware = described_class.new(app)
      status, headers, body = middleware.call(Rack::MockRequest.env_for("/", {}))

      expect(headers[described_class::ROLE_HEADER]).to eq(::ActiveRecord::Base.writing_role)

      RailsFailover::ActiveRecord.register_force_reading_role_callback do |env|
        true
      end

      status, headers, body = middleware.call(Rack::MockRequest.env_for("/", {}))

      expect(headers[described_class::ROLE_HEADER]).to eq(::ActiveRecord::Base.reading_role)
    ensure
      described_class.force_reading_role_callback = nil
    end
  end
end
