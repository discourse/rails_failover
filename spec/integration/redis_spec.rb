# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Redis failover", type: :redis do
  before do
    RailsFailover::Redis.verify_primary_frequency_seconds = 0.01
  end

  after do
    RailsFailover::Redis.verify_primary_frequency_seconds = nil
  end

  after do
    ObjectSpace.each_object(Redis::Client) { |r| r.disconnect }
    expect(RailsFailover::Redis::Handler.instance.send(:clients)).to eq({})
    system("make start_redis_primary")
  end

  it 'can failover to replica and recover to primary smoothly' do
    redis = create_redis_client
    expect(redis.info("replication")["role"]).to eq("master")

    system("make stop_redis_primary")

    expect { redis.ping }.to raise_error(Redis::CannotConnectError)

    expect(redis.info("replication")["role"]).to eq("slave")
    redis2 = create_redis_client
    expect(redis2.info("replication")["role"]).to eq("slave")

    system("make start_redis_primary")

    sleep 0.03

    expect(redis.info("replication")["role"]).to eq("master")
    expect(redis2.info("replication")["role"]).to eq("master")
    expect(create_redis_client.info("replication")["role"]).to eq("master")
  ensure
    system("make start_redis_primary")
  end

  it 'can failover to replica and recover to primary smoothly across forks' do
    RailsFailover::Redis::Handler.instance
    reader, writer = IO.pipe
    reader2, writer2 = IO.pipe
    reader3, writer3 = IO.pipe
    reader4, writer4 = IO.pipe

    child_pid = fork do
      writer.close
      writer3.close
      reader2.close
      reader4.close

      redis2 = create_redis_client
      expect(redis2.info("replication")["role"]).to eq("master")

      writer2.write("forked and waiting")

      IO.select([reader])

      expect { redis2.ping }.to raise_error(Redis::CannotConnectError)
      expect(redis2.info("replication")["role"]).to eq("slave")

      expect(redis2.info("replication")["role"]).to eq("slave")
      writer4.write("verified failover")

      IO.select([reader3])

      expect(redis2.info("replication")["role"]).to eq("master")
    ensure
      redis2&.disconnect!
    end

    reader.close
    reader3.close
    writer2.close
    writer4.close
    redis = create_redis_client

    expect(redis.info("replication")["role"]).to eq("master")

    IO.select([reader2])

    system("make stop_redis_primary")

    writer.write("primary stopped")

    expect { redis.ping }.to raise_error(Redis::CannotConnectError)
    expect(redis.info("replication")["role"]).to eq("slave")

    IO.select([reader4])

    system("make start_redis_primary")

    sleep 0.03

    writer3.write("started")

    expect(redis.info("replication")["role"]).to eq("master")

    Process.waitpid(child_pid)
  ensure
    system("make start_redis_primary")
  end

  it 'does not reuse handler thread after fork' do
    system("make stop_redis_primary")

    redis = create_redis_client

    expect(redis.info("replication")["role"]).to eq("slave")

    failover_called = {}

    RailsFailover::Redis.on_failover do
      failover_called[Process.pid] = true
    end

    reader, writer = IO.pipe

    fork do
      reader.close
      redis = create_redis_client

      expect(redis.info("replication")["role"]).to eq("slave")
      expect(failover_called[Process.pid]).to eq(true)

      writer.write("completed")
    end

    writer.close
    IO.select([reader])
  ensure
    RailsFailover::Redis.clear_callbacks
    system("make start_redis_primary")
  end

  it 'supports callbacks when failing over to primary and recovering back to primary' do
    primary_up_called = false
    primary_down_called = false

    RailsFailover::Redis.on_fallback do
      primary_up_called = true
    end

    RailsFailover::Redis.on_failover do
      primary_down_called = true
    end

    redis = create_redis_client
    expect(redis.ping).to eq("PONG")

    system("make stop_redis_primary")

    expect { redis.ping }.to raise_error(Redis::CannotConnectError)
    expect(primary_down_called).to eq(true)

    system("make start_redis_primary")

    sleep 0.03

    expect(primary_up_called).to eq(true)
  ensure
    RailsFailover::Redis.clear_callbacks
    system("make start_redis_primary")
  end

  it 'disconnects all active clients when a client detects that primary is down' do
    redis1 = create_redis_client
    redis2 = create_redis_client

    expect(redis1.ping).to eq("PONG")
    expect(redis2.ping).to eq("PONG")

    system("make stop_redis_primary")

    expect do
      expect { redis1.ping }.to raise_error(Redis::CannotConnectError)
    end.to change { redis1.connected? }.from(true).to(false)
      .and change { redis2.connected? }.from(true).to(false)
  ensure
    system("make start_redis_primary")
  end

  it 'does not deadlock during disconnections' do
    redis1 = create_redis_client
    redis2 = create_redis_client

    expect(redis1.ping).to eq("PONG")
    expect(redis2.ping).to eq("PONG")

    class <<redis1._client
      attr_accessor :fake_longrunning_command
      def call(commands)
        sleep 0.1 while fake_longrunning_command
        super
      end
    end
    redis1._client.fake_longrunning_command = true

    t1 = Thread.new do
      redis1.ping
    end

    system("make stop_redis_primary")

    t2 = Thread.new do
      expect { redis2.ping }.to raise_error(Redis::CannotConnectError)
    end

    redis1._client.fake_longrunning_command = false

    Timeout::timeout(5) do
      t1.join
      t2.join
    end

    # And now they should be failed over
    expect(redis1.ping).to eq("PONG")
    expect(redis2.ping).to eq("PONG")

    expect(redis1.info("replication")["role"]).to eq("slave")
    expect(redis2.info("replication")["role"]).to eq("slave")
  rescue Timeout::Error
    fail "Deadlock detected.\nThread 1: \n\n#{t1.backtrace.join("\n")}\n\nThread 2:\n\n#{t2.backtrace.join("\n")}\n\n"
  ensure
    system("make start_redis_primary")
    t1.exit
    t2.exit
  end

  it "handles long-running redis commands during fallback" do
    simple_redis = create_redis_client
    sub_redis = create_redis_client

    expect(simple_redis.ping).to eq("PONG")
    expect(sub_redis.ping).to eq("PONG")

    # Infinitely subscribe
    # This mimics things like message_bus
    subscriber = Thread.new do
      sub_redis.subscribe("mychannel") {}
    rescue Redis::BaseConnectionError => e
      puts "error #{e.class}, retry"
      retry
    rescue => e
      puts "error #{e.class}, exit"
    end

    system("make stop_redis_primary")
    sleep 0.2

    expect(simple_redis.ping).to eq("PONG")
    expect(simple_redis.connection[:port]).to eq(RedisHelper::REDIS_REPLICA_PORT)

    expect(sub_redis.connected?).to eq(true)
    expect(sub_redis.connection[:port]).to eq(RedisHelper::REDIS_REPLICA_PORT)

    system("make start_redis_primary")
    sleep 2

    expect(simple_redis.ping).to eq("PONG")
    expect(simple_redis.connection[:port]).to eq(RedisHelper::REDIS_PRIMARY_PORT)

    expect(sub_redis.connected?).to eq(true)
    expect(sub_redis.connection[:port]).to eq(RedisHelper::REDIS_PRIMARY_PORT)

  ensure
    system("make start_redis_primary")
    subscriber&.exit
  end

  it 'handles failover and fallback for different host/port combinations' do
    redis1 = create_redis_client
    redis2 = create_redis_client(host: "0.0.0.0", replica_host: "0.0.0.0")

    expect(redis1.ping).to eq("PONG")
    expect(redis2.ping).to eq("PONG")

    system("make stop_redis_primary")

    expect do
      expect(redis1.ping).to eq("PONG")
    end.to raise_error(Redis::CannotConnectError)

    expect do
      expect(redis2.ping).to eq("PONG")
    end.to raise_error(Redis::CannotConnectError)

    expect(redis1.info("replication")["role"]).to eq("slave")
    expect(redis2.info("replication")["role"]).to eq("slave")

    system("make start_redis_primary")

    sleep 0.03

    expect(redis1.info("replication")["role"]).to eq("master")
    expect(redis2.info("replication")["role"]).to eq("master")
  ensure
    system("make start_redis_primary")
  end
end
