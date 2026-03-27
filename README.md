# OMQ! Where did the C dependency go?!

[![CI](https://github.com/zeromq/omq/actions/workflows/ci.yml/badge.svg)](https://github.com/zeromq/omq/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/omq?color=e9573f)](https://rubygems.org/gems/omq)
[![License: ISC](https://img.shields.io/badge/License-ISC-blue.svg)](LICENSE)
[![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.3-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org)

Pure Ruby implementation of the [ZMTP 3.1](https://rfc.zeromq.org/spec/23/) wire protocol ([ZeroMQ](https://zeromq.org/)) using the [Async](https://github.com/socketry/async) gem. No native libraries required.

> **244k msg/s** inproc | **47k msg/s** ipc | **36k msg/s** tcp
>
> **9 µs** inproc latency | **47 µs** ipc | **61 µs** tcp
>
> Ruby 4.0 + YJIT on a Linux VM on a 2019 MacBook Pro (Intel) — [~340k msg/s with io_uring](bench/README.md#io_uring)

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
- **`io-stream`** — buffered I/O with read-ahead, from the Async ecosystem

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

All classes live under `OMQ::`. For the purists, `ØMQ` is an alias:

```ruby
req = ØMQ::REQ.new(">tcp://localhost:5555")
```

## Performance

Benchmarked with benchmark-ips on Linux x86_64 (Ruby 4.0.2 +YJIT):

#### Throughput (push/pull, 64 B messages)

| inproc | ipc | tcp |
|--------|-----|-----|
| 244k/s | 47k/s | 36k/s |

#### Latency (req/rep roundtrip)

| inproc | ipc | tcp |
|--------|-----|-----|
| 9 µs | 47 µs | 61 µs |

See [`bench/`](bench/) for full results and scripts.

## omqcat — CLI tool

`omqcat` is a command-line tool for sending and receiving messages on any OMQ socket. Like `nngcat` from libnng, but with Ruby superpowers.

```sh
# Echo server
omqcat rep -b tcp://:5555 --echo

# Upcase server in one line
omqcat rep -b tcp://:5555 -e '$F.map(&:upcase)'

# Client
echo "hello" | omqcat req -c tcp://localhost:5555
# => HELLO

# PUB/SUB
omqcat sub -b tcp://:5556 -s "weather."  &
echo "weather.nyc 72F" | omqcat pub -c tcp://localhost:5556 -d 0.3

# Pipeline with filtering
tail -f /var/log/syslog | omqcat push -c tcp://collector:5557
omqcat pull -b tcp://:5557 -e '$F.first.include?("error") ? $F : nil'

# Multipart messages via tabs
printf "routing-key\tpayload data" | omqcat push -c tcp://localhost:5557
omqcat pull -b tcp://:5557
# => routing-key	payload data

# JSONL for structured data
echo '["key","value"]' | omqcat push -c tcp://localhost:5557 -J
omqcat pull -b tcp://:5557 -J

# Zstandard compression
omqcat push -c tcp://remote:5557 -z < data.txt
omqcat pull -b tcp://:5557 -z

# CURVE encryption
omqcat rep -b tcp://:5555 -D "secret" --curve-server
# prints: OMQ_SERVER_KEY='...'
omqcat req -c tcp://localhost:5555 --curve-server-key '...'
```

The `-e` flag runs Ruby inside the socket instance — the full socket API (`self <<`, `send`, `subscribe`, ...) is available. Use `-r` to require gems:

```sh
omqcat sub -c tcp://localhost:5556 -s "" -r json \
  -e 'JSON.parse($F.first)["temperature"]'
```

Formats: `--ascii` (default, tab-separated), `--quoted`, `--raw`, `--jsonl`, `--msgpack`. See `omqcat --help` for all options.

## Interop with native ZMQ

OMQ speaks ZMTP 3.1 on the wire and interoperates with libzmq, CZMQ, pyzmq, etc. over **tcp** and **ipc**. The `inproc://` transport is OMQ-internal (in-process Ruby queues) and is not visible to native ZMQ running in the same process — use `ipc://` to talk across library boundaries.

## Development

```sh
bundle install
bundle exec rake
```

## License

[ISC](LICENSE)
