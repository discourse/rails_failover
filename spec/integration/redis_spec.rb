# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Redis failover", type: :redis do
  before do
    RailsFailover::Redis.verify_primary_frequency_seconds = 0.01
  end

  after do
    RailsFailover::Redis.verify_primary_frequency_seconds = nil
  end

  def join_handler_thread
    Timeout.timeout(10) do
      RailsFailover::Redis::Handler.instance.instance_variable_get(:@thread)&.join
    end
  end

  after do
    ObjectSpace.each_object(Redis::Client) { |r| r.disconnect }
    system("make start_redis_primary")
    join_handler_thread
    expect(RailsFailover::Redis::Handler.instance.send(:clients).values.all?(&:empty?)).to eq(true)
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

  it 'works correctly after fork' do
    system("make stop_redis_primary")

    redis = create_redis_client

    expect(redis.info("replication")["role"]).to eq("slave")

    failover_called = {}

    RailsFailover::Redis.on_failover do
      failover_called[Process.pid] = true
    end

    child_pid = fork do
      redis = create_redis_client
      expect(redis.info("replication")["role"]).to eq("slave")

      system("make start_redis_primary")
      join_handler_thread
      expect(redis.info("replication")["role"]).to eq("master")

      system("make stop_redis_primary")
      expect { redis.info("replication")["role"] }.to raise_error(Redis::BaseConnectionError)
      expect(redis.info("replication")["role"]).to eq("slave")

      expect(failover_called[Process.pid]).to eq(true)
    end

    _pid, status = Process.waitpid2(child_pid)
    expect(status).to eq(0)
  ensure
    RailsFailover::Redis.clear_callbacks
    system("make start_redis_primary")
  end

  it 'supports callbacks when failing over to primary and recovering back to primary' do
    primary_up_called = false
    primary_down_called = false

    RailsFailover::Redis.on_fallback do |key|
      primary_up_called = key
    end

    RailsFailover::Redis.on_failover do |key|
      primary_down_called = key
    end

    redis = create_redis_client
    expect(redis.ping).to eq("PONG")

    system("make stop_redis_primary")

    expect { redis.ping }.to raise_error(Redis::CannotConnectError)
    expect(primary_down_called).to eq(redis.id)

    system("make start_redis_primary")

    sleep 0.03

    expect(primary_up_called).to eq(redis.id)
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
      sleep 0.03
    end.to change { redis1.connected? }.from(true).to(false)
      .and change { redis2.connected? }.from(true).to(false)
  ensure
    system("make start_redis_primary")
  end

  it "handles long-running redis commands during fallback" do
    simple_redis = create_redis_client
    sub_redis = create_redis_client

    expect(simple_redis.ping).to eq("PONG")
    expect(sub_redis.ping).to eq("PONG")

    # Infinitely subscribe, mimicking message_bus
    subscriber = Thread.new do
      sub_redis.subscribe("mychannel") {}
    rescue Redis::BaseConnectionError
      retry
    end

    system("make stop_redis_primary")
    sleep 0.03

    expect(simple_redis.ping).to eq("PONG")
    expect(simple_redis.connection[:port]).to eq(RedisHelper::REDIS_REPLICA_PORT)

    expect(sub_redis.connected?).to eq(true)
    expect(sub_redis.connection[:port]).to eq(RedisHelper::REDIS_REPLICA_PORT)

    system("make start_redis_primary")

    join_handler_thread

    expect(simple_redis.ping).to eq("PONG")
    expect(simple_redis.connection[:port]).to eq(RedisHelper::REDIS_PRIMARY_PORT)

    expect(sub_redis.connected?).to eq(true)
    expect(sub_redis.connection[:port]).to eq(RedisHelper::REDIS_PRIMARY_PORT)

  ensure
    system("make start_redis_primary")
    subscriber&.exit
  end

  it "handles clients which are halfway though connection during fallback" do
    system("make stop_redis_primary")

    redis = create_redis_client
    client = redis.instance_variable_get(:@client)

    # Stub establish_connection so we can fake it taking a long time
    class << client
      attr_accessor :is_waiting

      def establish_connection
        super
        @is_waiting = true if @is_waiting.nil?
        Thread.pass until !@is_waiting
      end
    end

    # Start opening a redis connection to the replica
    t = Thread.new do
      expect { redis.ping }.to raise_error(Redis::CannotConnectError)
      expect(redis.ping).to eq("PONG")
    end
    Thread.pass until client.is_waiting

    # While it's opening, start the primary
    system("make start_redis_primary")
    sleep 0.03

    # Trigger fallback
    expect(create_redis_client.ping).to eq("PONG")
    join_handler_thread

    # Unblock the replica connection from earlier
    client.is_waiting = false
    t.join

    # It should realise that the primary is back online
    expect(redis.connection[:port]).to eq(RedisHelper::REDIS_PRIMARY_PORT)
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

  it 'does not break when primary is same as replica' do
    redis = create_redis_client(replica_port: RedisHelper::REDIS_PRIMARY_PORT)

    expect(redis.ping).to eq("PONG")
    system("make stop_redis_primary")

    # Failover won't actually work - connection errors will be raised consistently
    expect { redis.ping }.to raise_error(Redis::CannotConnectError)
    expect { redis.ping }.to raise_error(Redis::CannotConnectError)

    system("make start_redis_primary")

    sleep 0.03

    expect(redis.ping).to eq("PONG")
  ensure
    system("make start_redis_primary")
  end

  it "recovers even if the replica goes offline" do
    redis = create_redis_client
    expect(redis.info("replication")["role"]).to eq("master")

    system("make stop_redis_primary")

    expect { redis.ping }.to raise_error(Redis::CannotConnectError)

    expect(redis.info("replication")["role"]).to eq("slave")

    system("make stop_redis_replica")

    expect { redis.ping }.to raise_error(Redis::CannotConnectError)

    system("make start_redis_replica")

    sleep 0.03

    expect(redis.info("replication")["role"]).to eq("slave")

    system("make start_redis_primary")

    sleep 0.03

    expect(redis.info("replication")["role"]).to eq("master")
  end
end
