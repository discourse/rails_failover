PORT               := 6381
PID_PATH           := /tmp/redis.pid
SOCKET_PATH        := /tmp/redis.sock
DBFILENAME         := master.rdb
replica_port         := 6382
REPLICA_PID_PATH     := /tmp/redis_replica.pid
REPLICA_SOCKET_PATH  := /tmp/redis_replica.sock
REPLICA_DBFILENAME   := replica.rdb

default:
	@make -s all

all: redis

redis: start_redis test_redis stop_redis

test_redis:
	bundle exec rspec --tag type:redis ${RSPEC_PATH}

start_redis: start_redis_master start_redis_replica
stop_redis: stop_redis_replica stop_redis_master

stop_redis_master:
	@redis-cli -p ${PORT} shutdown

start_redis_master:
	@redis-server --daemonize yes --pidfile ${PID_PATH} --port ${PORT} --unixsocket ${SOCKET_PATH} --dbfilename ${DBFILENAME} --logfile /dev/null

stop_redis_replica:
	@redis-cli -p ${replica_port} shutdown

start_redis_replica:
	@redis-server --daemonize yes --pidfile ${REPLICA_PID_PATH} --port ${replica_port} --unixsocket ${REPLICA_SOCKET_PATH} --replicaof 127.0.0.1 ${PORT} --dbfilename ${REPLICA_DBFILENAME} --logfile /dev/null
