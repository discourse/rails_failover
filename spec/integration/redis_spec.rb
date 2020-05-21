# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Redis failover", type: :redis do
  before do
    RailsFailover::Redis.verify_master_frequency_seconds = 0.01
  end

  after do
    RailsFailover::Redis.verify_master_frequency_seconds = nil
  end

  after do
    ObjectSpace.each_object(Redis) { |r| r.disconnect! }
    expect(RailsFailover::Redis::Handler.instance.clients).to eq([])
    system("make start_redis_master")
  end

  it 'can failover to replica and recover to master smoothly' do
    redis = create_redis_client
    expect(redis.info("replication")["role"]).to eq("master")

    system("make stop_redis_master")

    expect { redis.ping }.to raise_error(Redis::CannotConnectError)

    expect(redis.info("replication")["role"]).to eq("slave")
    redis2 = create_redis_client
    expect(redis2.info("replication")["role"]).to eq("slave")

    system("make start_redis_master")

    sleep 0.03

    expect(redis.info("replication")["role"]).to eq("master")
    expect(redis2.info("replication")["role"]).to eq("master")
    expect(create_redis_client.info("replication")["role"]).to eq("master")
  end

  it 'can failover to replica and recover to master smoothly across forks' do
    reader, writer = IO.pipe
    reader2, writer2 = IO.pipe
    reader3, writer3 = IO.pipe

    child_pid = fork do
      writer.close
      writer3.close
      reader2.close

      redis2 = create_redis_client
      expect(redis2.info("replication")["role"]).to eq("master")

      writer2.write("forked and waiting")

      IO.select([reader])

      expect { redis2.ping }.to raise_error(Redis::CannotConnectError)
      expect(redis2.info("replication")["role"]).to eq("slave")

      IO.select([reader3])

      expect(redis2.info("replication")["role"]).to eq("master")
    ensure
      redis2&.disconnect!
    end

    reader.close
    reader3.close
    writer2.close
    redis = create_redis_client

    expect(redis.info("replication")["role"]).to eq("master")

    IO.select([reader2])

    system("make stop_redis_master")

    writer.write("stopped")

    expect { redis.ping }.to raise_error(Redis::CannotConnectError)
    expect(redis.info("replication")["role"]).to eq("slave")

    system("make start_redis_master")

    sleep 0.03

    writer3.write("started")

    expect(redis.info("replication")["role"]).to eq("master")

    Process.waitpid(child_pid)
  end

  it 'supports callbacks when failing over to master and recovering back to master' do
    master_up_called = false
    master_down_called = false

    RailsFailover::Redis.register_master_up_callback do
      master_up_called = true
    end

    RailsFailover::Redis.register_master_down_callback do
      master_down_called = true
    end

    redis = create_redis_client
    expect(redis.ping).to eq("PONG")

    system("make stop_redis_master")

    expect { redis.ping }.to raise_error(Redis::CannotConnectError)
    expect(master_down_called).to eq(true)

    system("make start_redis_master")

    sleep 0.03

    expect(master_up_called).to eq(true)
  ensure
    RailsFailover::Redis.master_up_callbacks.clear
    RailsFailover::Redis.master_down_callbacks.clear
  end

  it 'disconnects all active clients when a client detects that master is down' do
    redis1 = create_redis_client
    redis2 = create_redis_client

    expect(redis1.ping).to eq("PONG")
    expect(redis2.ping).to eq("PONG")

    system("make stop_redis_master")

    expect do
      expect { redis1.ping }.to raise_error(Redis::CannotConnectError)
    end.to change { redis1.connected? }.from(true).to(false)
      .and change { redis2.connected? }.from(true).to(false)
  end
end
