# OMQ — ZeroMQ in pure Ruby

[![CI](https://github.com/zeromq/omq/actions/workflows/ci.yml/badge.svg)](https://github.com/zeromq/omq/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/omq?color=e9573f)](https://rubygems.org/gems/omq)
[![License: ISC](https://img.shields.io/badge/License-ISC-blue.svg)](LICENSE)
[![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.3-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org)

`gem install omq` — that's it. No libzmq, no compiler, no system packages. Just Ruby.

OMQ implements the [ZMTP 3.1](https://rfc.zeromq.org/spec/23/) wire protocol from scratch using [Async](https://github.com/socketry/async) fibers. It speaks native ZeroMQ on the wire and interoperates with libzmq, pyzmq, CZMQ, and everything else in the ZMQ ecosystem.

> **234k msg/s** inproc | **49k msg/s** ipc | **36k msg/s** tcp
>
> **12 µs** inproc latency | **51 µs** ipc | **62 µs** tcp
>
> Ruby 4.0 + YJIT on a Linux VM — see [`bench/`](bench/) for full results

---

## What is ZeroMQ?

Brokerless message-oriented middleware. No central server, no extra hop — processes talk directly to each other, cutting latency in half compared to broker-based systems. You get the patterns you'd normally build on top of RabbitMQ or Redis — pub/sub, work distribution, request/reply, fan-out — but decentralized, with no single point of failure.

Networking is hard. ZeroMQ abstracts away reconnection, queuing, load balancing, and framing so you can focus on what your system actually does. Start with threads talking over `inproc://`, split into processes with `ipc://`, scale across machines with `tcp://` — same code, same API, just change the URL.

If you've ever wired up services with raw TCP, HTTP polling, or Redis pub/sub and wished it was simpler, this is what you've been looking for.

See [GETTING_STARTED.md](GETTING_STARTED.md) for a ~30 min walkthrough of all major patterns with working code.

## Highlights

- **Zero dependencies on C** — no extensions, no FFI, no libzmq. `gem install` just works everywhere
- **Fast** — YJIT-optimized hot paths, batched sends, 234k msg/s inproc with 12 µs latency
- **`omq` CLI** — pipe, filter, and transform messages from the terminal with Ruby eval, Ractor parallelism, and [script handlers](CLI.md#script-handlers--r)
- **Every socket pattern** — req/rep, pub/sub, push/pull, dealer/router, xpub/xsub, pair, and all draft types
- **Every transport** — tcp, ipc (Unix domain sockets), inproc (in-process queues)
- **Async-native** — built on fibers, non-blocking from the ground up. A shared IO thread handles sockets outside of Async — no reactor needed for simple scripts
- **Wire-compatible** — interoperates with libzmq, pyzmq, CZMQ over tcp and ipc
- **Bind/connect order doesn't matter** — connect before bind, bind before connect, peers come and go. ZeroMQ reconnects and requeues automatically

For architecture internals, see [DESIGN.md](DESIGN.md).

## Install

No system libraries needed — just Ruby:

```sh
gem install omq
# or in Gemfile
gem 'omq'
```

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
  p req.receive  # => ["HELLO"]
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
  p sub.receive  # => ["news flash"]
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
  p pull.receive  # => ["work item"]
ensure
  push&.close
  pull&.close
end
```

### Without Async (IO thread)

OMQ spawns a shared `omq-io` thread when used outside an Async reactor — no boilerplate needed:

```ruby
require 'omq'

push = OMQ::PUSH.bind('tcp://127.0.0.1:5557')
pull = OMQ::PULL.connect('tcp://127.0.0.1:5557')

push << 'hello'
p pull.receive  # => ["hello"]

push.close
pull.close
```

The IO thread runs all pumps, reconnection, and heartbeating in the background. When you're inside an `Async` block, OMQ uses the existing reactor instead.

## Socket Types

All sockets are thread-safe. Default HWM is 1000 messages per socket. Classes live under `OMQ::` (alias: `ØMQ`).

#### Standard (multipart messages)

| Pattern | Send | Receive | When HWM full |
|---------|------|---------|---------------|
| **REQ** / **REP** | Round-robin / route-back | Fair-queue | Block |
| **PUB** / **SUB** | Fan-out to subscribers | Subscription filter | Drop |
| **PUSH** / **PULL** | Round-robin to workers | Fair-queue | Block |
| **DEALER** / **ROUTER** | Round-robin / identity-route | Fair-queue | Block |
| **XPUB** / **XSUB** | Fan-out (subscription events) | Fair-queue | Drop |
| **PAIR** | Exclusive 1-to-1 | Exclusive 1-to-1 | Block |

#### Draft (single-frame only)

| Pattern | Send | Receive | When HWM full |
|---------|------|---------|---------------|
| **CLIENT** / **SERVER** | Round-robin / routing-ID | Fair-queue | Block |
| **RADIO** / **DISH** | Group fan-out | Group filter | Drop |
| **SCATTER** / **GATHER** | Round-robin | Fair-queue | Block |
| **PEER** | Routing-ID | Fair-queue | Block |
| **CHANNEL** | Exclusive 1-to-1 | Exclusive 1-to-1 | Block |

## omq — CLI tool

`omq` is a command-line tool for sending and receiving messages on any OMQ socket. Like `nngcat` from libnng, but with Ruby superpowers.

```sh
# Echo server
omq rep -b tcp://:5555 --echo

# Upcase server — -e evals Ruby on each incoming message
omq rep -b tcp://:5555 -e '$F.map(&:upcase)'

# Client
echo "hello" | omq req -c tcp://localhost:5555
# => HELLO

# PUB/SUB
omq sub -b tcp://:5556 -s "weather."  &
echo "weather.nyc 72F" | omq pub -c tcp://localhost:5556 -d 0.3

# Pipeline with filtering
tail -f /var/log/syslog | omq push -c tcp://collector:5557
omq pull -b tcp://:5557 -e 'next unless /error/; $F'

# Transform outgoing messages with -E
echo hello | omq push -c tcp://localhost:5557 -E '$F.map(&:upcase)'

# REQ: transform request and reply independently
echo hello | omq req -c tcp://localhost:5555 \
  -E '$F.map(&:upcase)' -e '$F.map(&:reverse)'

# Pipe: PULL → eval → PUSH in one process
omq pipe -c ipc://@work -c ipc://@sink -e '$F.map(&:upcase)'

# Pipe with Ractor workers for CPU parallelism (-P = all CPUs)
omq pipe -c ipc://@work -c ipc://@sink -P -r./fib -e 'fib(Integer($_)).to_s'
```

`-e` (recv-eval) transforms incoming messages, `-E` (send-eval) transforms outgoing messages. `$F` is the message parts array, `$_` is the first part. Use `-r` to require gems or load scripts that register handlers via `OMQ.incoming` / `OMQ.outgoing`:

```ruby
# my_handler.rb
db = DB.connect("postgres://localhost/app")

OMQ.incoming { db.query($F.first) }
at_exit { db.close }
```

```sh
omq pull -b tcp://:5557 -r./my_handler.rb
```

See [CLI.md](CLI.md) for full documentation, or `omq --help` / `omq --examples`.

## Development

```sh
bundle install
bundle exec rake
```

## License

[ISC](LICENSE)
