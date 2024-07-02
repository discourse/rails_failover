# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe "ActiveRecord failover", type: :active_record do
  EXPECTED_POSTS_COUNT = "100"

  def start_dummy_rails_server
    raise "Could not start dummy server" if !system("make start_dummy_rails_server")
  end

  def stop_dummy_rails_server
    system("make stop_dummy_rails_server")
  end

  def restart_dummy_rails_server
    stop_dummy_rails_server
    start_dummy_rails_server
  end

  # rubocop:disable RSpec/BeforeAfterAll
  before(:all) { start_dummy_rails_server }

  after(:all) { stop_dummy_rails_server }

  it "should failover to reading connection handler when PG primary is down and fallback to writing connection handler when PG primary is back up" do
    response = get("/posts")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: writing
    BODY

    system("make stop_pg_primary")

    get("/posts") # Trigger process to failover

    response = get("/posts")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: reading
    BODY

    system("make start_pg_primary") # Start the fallback process

    sleep 0.05

    response = get("/posts")

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: writing
    BODY
  ensure
    system("make restart_pg_primary")
  end

  it "should be able to start with the PG primary being down" do
    stop_dummy_rails_server
    system("make stop_pg_primary")
    start_dummy_rails_server

    response = get("/posts")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: reading
    BODY

    system("make start_pg_primary")

    sleep 0.05

    response = get("/posts")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: writing
    BODY
  ensure
    system("make restart_pg_primary")
  end

  it "supports multiple databases automatically" do
    response = get("/posts?role=two_writing")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: two_writing
    BODY

    system("make stop_pg_primary")

    get("/posts?role=two_writing") # Trigger process to failover

    response = get("/posts?role=two_writing")

    expect(response.code.to_i).to eq(200)

    expect(response.body).to eq(<<~BODY.chomp)
    Posts count: #{EXPECTED_POSTS_COUNT}
    role: two_reading
    BODY
  ensure
    system("make start_pg_primary")
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
    let(:path) do
      Pathname.new("#{__dir__}/../support/dummy_app/triggered_from_pg_exception.writing")
    end

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

    after { FileUtils.cp(replicas_config, db_config) }

    it "does not prevent Rails from loading" do
      expect { restart_dummy_rails_server }.not_to raise_error
    end
  end
end
