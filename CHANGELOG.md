# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.9] - 2020-11-06
- FIX: Ignore errors from the redis socket shutdown call

  This can fail with various i/o errors, but in all cases we want the thread to continue closing the connection with the error, and all the other connections.

## [0.5.8] - 2020-11-05

- FIX: Handle concurrency issues during redis disconnection (#10)

  This handles concurrency issues which can happen during redis failover/fallback:
  - Previously, 'subscribed' redis clients were skipped during the disconnect process. This is resolved by directly accessing the original_client from the ::Redis instance
  - Trying to acquire the mutex on a subscribed redis client is impossible, so the close operation would never complete. Now we send the shutdown() signal to the thread, then allow up to 1 second for the mutex to be released before we close the socket
  - Failover is almost always triggered inside a redis client mutex. Failover then has its own mutex, within which we attempted to acquire mutexes for all redis clients. This logic causes a deadlock when multiple clients failover simultaneously. Now, all disconnection is performed by the Redis::Handler failover thread, outside of any other mutexes. To make this safe, the primary/replica state is stored in the connection driver, and disconnect_clients is updated to specifically target primary/replica connections.

## [0.5.7] - 2020-09-16

- FIX: Avoid disconnecting Redis connections abruptly.

## [0.5.6] - 2020-09-14

- FIX: Iteration and mutation of primaries_down in separate threads (#5)

  Ruby hashes can't be modified whilst they are being iterated over.

  Here, the primaries_down hash is iterated over to check each previously
  unavailable primary to see if it is now contactable. However, since this
  hash can be updated in other threads, this iteration isn't safe.

  To prevent this, a copy of the hash is iterated over instead.

  The GIL should not be released during a hash dup [1], but let's not tie
  ourselves unnecessarily to current MRI behaviour.

  [1]: https://github.com/ruby-concurrency/concurrent-ruby/issues/528

## [0.5.5] - 2020-08-04

- FIX: Rescue from `Redis::TimeoutError` instead of `Timeout::Error`.

## [0.5.4] - 2020-07-21

- FIX: Undefined method on nil class error in forking servers.

## [0.5.3] - 2020-07-20

- FIX: Incorrectly rescuing from `PG::ServerError`.

## [0.5.2] - 2020-06-23

### Changed
- FIX: Only rescue from connection errors.
