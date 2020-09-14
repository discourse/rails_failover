# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
