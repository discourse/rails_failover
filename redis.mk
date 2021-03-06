REDIS_PORT                 := 6381
REDIS_PID_PATH             := /tmp/redis.pid
REDIS_SOCKET_PATH          := /tmp/redis.sock
REDIS_DBFILENAME           := primary.rdb
REDIS_REPLICA_PORT         := 6382
REDIS_REPLICA_PID_PATH     := /tmp/redis_replica.pid
REDIS_REPLICA_SOCKET_PATH  := /tmp/redis_replica.sock
REDIS_REPLICA_DBFILENAME   := replica.rdb

redis: start_redis test_redis stop_redis

test_redis:
	@REDIS=1 bundle exec rspec --tag type:redis ${RSPEC_PATH}

start_redis: start_redis_primary start_redis_replica
stop_redis: stop_redis_replica stop_redis_primary

stop_redis_primary:
	@redis-cli -p ${REDIS_PORT} shutdown

start_redis_primary:
	@redis-server --daemonize yes --pidfile ${REDIS_PID_PATH} --port ${REDIS_PORT} --unixsocket ${REDIS_SOCKET_PATH} --dbfilename ${REDIS_DBFILENAME} --logfile /dev/null

stop_redis_replica:
	@redis-cli -p ${REDIS_REPLICA_PORT} shutdown

start_redis_replica:
	@redis-server --daemonize yes --pidfile ${REDIS_REPLICA_PID_PATH} --port ${REDIS_REPLICA_PORT} --unixsocket ${REDIS_REPLICA_SOCKET_PATH} --slaveof 127.0.0.1 ${REDIS_PORT} --dbfilename ${REDIS_REPLICA_DBFILENAME} --logfile /dev/null
