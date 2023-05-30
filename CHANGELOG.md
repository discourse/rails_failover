# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.1] - 2023-05-30

- FIX: Use `next` instead of `break` to avoid a local jump error

## [2.0.0] - 2023-05-16

- DEV: Compatibility with Rails 7.1+ (drop support for Rails 6.0 & ruby 2.7)

## [1.0.0] - 2023-04-07

- DEV: Remove the support for Ruby < 2.7
- DEV: Compatibility with Rails 7.1+

## [0.8.0] - 2022-01-17

- FEATURE: Compatibility with Rails 7.0+

## [0.7.3] - 2021-04-15

- FEATURE: Compatibility with Rails 6.1

## [0.7.2] - 2021-04-14

No changes.

## [0.7.1] - 2021-04-14

- FIX: Backward compatibility with Rails 6.0

## [0.7.0] - 2021-04-14

- FEATURE: Partial compatibility with Rails 6.1

## [0.6.5] - 2020-12-16

- FIX: Catch exceptions that are not intercepted by `ActionDispatch::DebugExceptions`.

## [0.6.4] - 2020-12-09

- FIX: Handle the case when the replica is set equal to the primary

## [0.6.3] - 2020-12-07

- FIX: Handle clients which are connecting during fallback

## [0.6.2] - 2020-11-19

- FIX: Use concurrent-ruby maps to simplify concurrency logic. Resolves a number of possible concurrency issues

## [0.6.1] - 2020-11-19

- FIX: Recover correctly if both the primary and replica go offline

  Previously, a replica failing would cause it to be added to the 'primaries_down' list. The fallback handler would then continuously try and fallback the replica to itself, looping forever, and meaning that fallback to primary would never happen.

## [0.6.0] - 2020-11-09

- FEATURE: Run failover/fallback callbacks once for each backend

  Previously the failover callback would only fire when the first backend failed, and the fallback callback would only fire when the last backend recovered. Now both failover and fallback callbacks will be triggered for each backend. The key for each backend is also passed to the callbacks for consumption by consuming applications.

- FEATURE: Add primaries_down_count function to failover handlers

  This is intended for consumption by monitoring systems (e.g. the Discourse prometheus exporter)

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
