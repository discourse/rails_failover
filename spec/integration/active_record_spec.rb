# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "ActiveRecord failover", type: :active_record do
  EXPECTED_POSTS_COUNT = "100"

  def start_dummy_rails_server
    system("make start_dummy_rails_server")
  end

  def stop_dummy_rails_server
    system("make stop_dummy_rails_server")
  end

  before(:all) do
    start_dummy_rails_server
  end

  after(:all) do
    stop_dummy_rails_server
  end

  it "Rails app should failover to reading connection handler when PG primary " \
    "is down and fallback to writing connection handler when PG primary is back up" do

    response = get("/posts")

    expect(response.code.to_i).to eq(200)
    expect(response.body).to include("writing")
    expect(response.body).to include(EXPECTED_POSTS_COUNT)

    system("make stop_pg_primary")

    flood_get("/posts", times: 10) # Trigger all processes to failover

    flood_get("/posts", times: 100) do |res|
      expect(res.code.to_i).to eq(200)
      expect(res.body).to include("reading")
      expect(res.body).to include(EXPECTED_POSTS_COUNT)
    end
  ensure
    system("make restart_pg_primary")
  end

  it "Rails app should be able to start with the PG primary being down" do
    stop_dummy_rails_server
    system("make stop_pg_primary")
    start_dummy_rails_server

    flood_get("/posts", times: 100) do |response|
      expect(response.code.to_i).to eq(200)
      expect(response.body).to include("reading")
    end

    system("make start_pg_primary")

    sleep 0.05

    flood_get("/posts", times: 100) do |response|
      expect(response.code.to_i).to eq(200)
      expect(response.body).to include("writing")
    end
  ensure
    system("make restart_pg_primary")
  end

  it 'supports multiple databases automatically' do
    response = get("/posts?role=two_writing")

    expect(response.code.to_i).to eq(200)
    expect(response.body).to include("two_writing")

    system("make stop_pg_primary")

    flood_get("/posts?role=two_writing", times: 10) # Trigger all processes to failover

    flood_get("/posts?role=two_writing", times: 100) do |resp|
      expect(resp.code.to_i).to eq(200)
      expect(resp.body).to include("two_reading")
    end
  ensure
    system("make start_pg_primary")
  end
end
