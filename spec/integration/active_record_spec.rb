# frozen_string_literal: true

require "fileutils"

RSpec.describe "ActiveRecord failover", type: :active_record do
  EXPECTED_POSTS_COUNT = "100"

  def restart_dummy_rails_server
    stop_rails_server
    start_rails_server
  end

  # rubocop:disable RSpec/BeforeAfterAll
  before(:all) do
    start_pg_primary
    start_pg_replica
    setup_rails_server
    start_rails_server
  end

  after do
    start_pg_primary
    start_rails_server
  end

  after(:all) do
    stop_rails_server
    stop_pg_replica
    stop_pg_primary
  end

  it "should failover to reading connection handler when PG primary is down and fallback to writing connection handler when PG primary is back up" do
    response = get("/posts")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: writing
    BODY

    stop_pg_primary

    get("/posts") # Trigger process to failover

    response = get("/posts")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: reading
    BODY

    start_pg_primary # Start the fallback process

    sleep 0.05 # Wait for fallback to complete

    response = get("/posts")

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: writing
    BODY
  end

  it "should be able to start with the PG primary being down" do
    stop_rails_server
    stop_pg_primary

    retry_count = 0

    begin
      start_rails_server
    rescue => e
      if ENV["GITHUB_ACTIONS"] && retry_count < 2
        # We're getting the following error only on CI but not locally and I don't really know why but have spent too much
        # time debugging. Just retry until we can start the Rails server.
        #
        # bundler: failed to load command: unicorn (/opt/hostedtoolcache/Ruby/3.4.0-preview1/x64/bin/unicorn)
        #   /opt/hostedtoolcache/Ruby/3.4.0-preview1/x64/lib/ruby/3.4.0+0/bundled_gems.rb:80:in 'Kernel.require': stream closed in another thread (IOError)
        retry_count += 1
        sleep 1
        retry
      end
    end

    response = get("/posts")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: reading
    BODY

    start_pg_primary

    sleep 0.05 # Wait for fallback to complete

    response = get("/posts")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: writing
    BODY
  end

  it "supports multiple databases automatically" do
    response = get("/posts?role=two_writing")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: two_writing
    BODY

    stop_pg_primary

    get("/posts?role=two_writing") # Trigger process to failover

    response = get("/posts?role=two_writing")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: two_reading
    BODY
  end

  it "should not failover on PG server errors" do
    response = get("/trigger-pg-server-error")

    expect(response.code.to_i).to eq(500)

    response = get("/posts")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: writing
    BODY
  end

  context "when PG exception is raised before ActionDispatch::DebugExceptions" do
    let(:path) { Pathname.new("/tmp/triggered_from_pg_exception.writing") }

    after { FileUtils.rm_f(path) }

    it "fails over" do
      response = get("/trigger-middleware-pg-exception")

      expect(response.code.to_i).to eq(500)

      sleep 0.05

      response = get("/posts")

      expect(response.code.to_i).to eq(200)
      expect(path.exist?).to be true
    end
  end

  context "when there is no replica config for the DB" do
    let(:config_path) { Pathname.new("#{__dir__}/../support/dummy_app/config") }
    let(:replicas_config) { config_path / "database.replicas.yml" }
    let(:no_replicas_config) { config_path / "database.no-replicas.yml" }
    let(:db_config) { config_path / "database.yml" }

    before { FileUtils.cp(no_replicas_config, db_config) }

    after do
      FileUtils.cp(replicas_config, db_config)
      restart_dummy_rails_server
    end

    it "does not prevent Rails from loading" do
      expect { restart_dummy_rails_server }.not_to raise_error
    end
  end
end
