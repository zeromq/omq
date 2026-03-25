# OMQ! Where did the C dependency go?!

[![CI](https://github.com/paddor/omq/actions/workflows/ci.yml/badge.svg)](https://github.com/paddor/omq/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/omq?color=e9573f)](https://rubygems.org/gems/omq)
[![License: ISC](https://img.shields.io/badge/License-ISC-blue.svg)](LICENSE)
[![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.3-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org)

Pure Ruby implementation of the [ZMTP 3.1](https://rfc.zeromq.org/spec/23/) wire protocol ([ZeroMQ](https://zeromq.org/)) using the [Async](https://github.com/socketry/async) gem. No native libraries required.

> **186k msg/s** inproc throughput | **12 µs** req/rep roundtrip latency | pure Ruby + YJIT

---

## Highlights

- **Pure Ruby** — no C extensions, no FFI, no libzmq/libczmq dependency
- **All socket types** — req/rep, pub/sub, push/pull, dealer/router, xpub/xsub, pair
- **Async-native** — built on [Async](https://github.com/socketry/async) fibers, also works with plain threads
- **Ruby-idiomatic API** — messages as `Array<String>`, errors as exceptions, timeouts as `IO::TimeoutError`
- **All transports** — tcp, ipc, inproc

## Why pure Ruby?

Modern Ruby has closed the gap:

- **YJIT** — JIT-compiled hot paths close the throughput gap with C extensions
- **Fiber Scheduler** — non-blocking I/O without callbacks or threads (`Async` builds on this)
- **`IO::Buffer`** — zero-copy binary reads/writes, no manual `String#b` packing

When [CZTop](https://github.com/paddor/cztop) was written, none of this existed. Today, a pure Ruby ZMTP implementation is fast enough for production use — and you get `gem install` with no compiler toolchain, no system packages, and no segfaults.

## Install

No system libraries needed — just Ruby:

```sh
gem install omq
# or in Gemfile
gem 'omq'
```

## Learning ZeroMQ

New to ZeroMQ? See [ZGUIDE_SUMMARY.md](ZGUIDE_SUMMARY.md) — a ~30 min read covering all major patterns with working OMQ code examples.

## Quick Start

### Request / Reply

```ruby
require 'omq'
require 'async'

Async do |task|
  rep = OMQ::REP.bind('inproc://example')
  req = OMQ::REQ.connect('inproc://example')

  task.async do
    msg = rep.receive
    rep << msg.map(&:upcase)
  end

  req << 'hello'
  puts req.receive.inspect  # => ["HELLO"]
ensure
  req&.close
  rep&.close
end
```

### Pub / Sub

```ruby
Async do |task|
  pub = OMQ::PUB.bind('inproc://pubsub')
  sub = OMQ::SUB.connect('inproc://pubsub')
  sub.subscribe('')  # subscribe to all

  task.async { pub << 'news flash' }
  puts sub.receive.inspect  # => ["news flash"]
ensure
  pub&.close
  sub&.close
end
```

### Push / Pull (Pipeline)

```ruby
Async do
  push = OMQ::PUSH.connect('inproc://pipeline')
  pull = OMQ::PULL.bind('inproc://pipeline')

  push << 'work item'
  puts pull.receive.inspect  # => ["work item"]
ensure
  push&.close
  pull&.close
end
```

## Socket Types

| Pattern | Classes | Direction |
|---------|---------|-----------|
| Request/Reply | `REQ`, `REP` | bidirectional |
| Publish/Subscribe | `PUB`, `SUB`, `XPUB`, `XSUB` | unidirectional |
| Pipeline | `PUSH`, `PULL` | unidirectional |
| Routing | `DEALER`, `ROUTER` | bidirectional |
| Exclusive pair | `PAIR` | bidirectional |

All classes live under `OMQ::`.

## Performance

Benchmarked with benchmark-ips on Linux x86_64 (Ruby 4.0.1 +YJIT):

#### Throughput (push/pull, 64 B messages)

| inproc | ipc | tcp |
|--------|-----|-----|
| 184k/s | 35k/s | 18k/s |

#### Latency (req/rep roundtrip)

| inproc | ipc | tcp |
|--------|-----|-----|
| 13 µs | 70 µs | 97 µs |

See [`bench/`](bench/) for full results and scripts.

## Interop with native ZMQ

OMQ speaks ZMTP 3.1 on the wire and interoperates with libzmq, CZMQ, pyzmq, etc. over **tcp** and **ipc**. The `inproc://` transport is OMQ-internal (in-process Ruby queues) and is not visible to native ZMQ running in the same process — use `ipc://` to talk across library boundaries.

## Development

```sh
bundle install
bundle exec rake
```

## License

[ISC](LICENSE)
