# OMQ — Where did the C dependency go!?

[![CI](https://github.com/zeromq/omq/actions/workflows/ci.yml/badge.svg)](https://github.com/zeromq/omq/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/omq?color=e9573f)](https://rubygems.org/gems/omq)
[![License: ISC](https://img.shields.io/badge/License-ISC-blue.svg)](LICENSE)
[![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.3-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org)

`gem install omq` — that's it. No libzmq, no compiler, no system packages. Just Ruby.

OMQ builds ZeroMQ socket patterns on top of [protocol-zmtp](https://github.com/paddor/protocol-zmtp) (a pure Ruby [ZMTP 3.1](https://rfc.zeromq.org/spec/23/) codec) using [Async](https://github.com/socketry/async) fibers. It speaks native ZeroMQ on the wire and interoperates with libzmq, pyzmq, CZMQ, and everything else in the ZMQ ecosystem.

> **980k msg/s** inproc | **38k msg/s** ipc | **31k msg/s** tcp
>
> **10 µs** inproc latency | **71 µs** ipc | **82 µs** tcp
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
- **Fast** — YJIT-optimized hot paths, batched sends, recv prefetching, direct-pipe inproc bypass. 980k msg/s inproc, 10 µs latency
- **[`omq` CLI](https://github.com/paddor/omq-cli)** — `gem install omq-cli` for a command-line tool with Ruby eval, Ractor parallelism, and script handlers
- **Every socket pattern** — req/rep, pub/sub, push/pull, dealer/router, xpub/xsub, pair, and all draft types
- **Every transport** — tcp, ipc (Unix domain sockets), inproc (in-process queues)
- **Async-native** — built on fibers, non-blocking from the ground up. A shared IO thread handles sockets outside of Async — no reactor needed for simple scripts
- **Wire-compatible** — interoperates with libzmq, pyzmq, CZMQ over tcp and ipc
- **Bind/connect order doesn't matter** — connect before bind, bind before connect, peers come and go. ZeroMQ reconnects automatically and queued messages drain when peers arrive

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

### Queue Interface

All sockets expose an `Async::Queue`-inspired interface:

| Async::Queue | OMQ Socket | Notes |
|---|---|---|
| `enqueue(item)` / `push(item)` | `enqueue(msg)` / `push(msg)` | Also: `send(msg)`, `<< msg` |
| `dequeue(timeout:)` / `pop(timeout:)` | `dequeue(timeout:)` / `pop(timeout:)` | Defaults to socket's `read_timeout` |
| `wait` | `wait` | Blocks indefinitely (ignores `read_timeout`) |
| `each` | `each` | Yields messages; returns on close or timeout |

```ruby
pull = OMQ::PULL.bind('inproc://work')

# iterate messages like a queue
pull.each do |msg|
  puts msg.first
end
```

## Socket Types

All sockets are thread-safe. Default HWM is 1000 messages per socket. `max_message_size` defaults to **`nil` (unlimited)** — set `socket.max_message_size = N` to cap inbound frames at `N` bytes; oversized frames cause the connection to be dropped before the body is read from the wire. Classes live under `OMQ::` (alias: `ØMQ`).

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

These require the `omq-draft` gem.

| Pattern | Send | Receive | When HWM full |
|---------|------|---------|---------------|
| **CLIENT** / **SERVER** | Round-robin / routing-ID | Fair-queue | Block |
| **RADIO** / **DISH** | Group fan-out | Group filter | Drop |
| **SCATTER** / **GATHER** | Round-robin | Fair-queue | Block |
| **PEER** | Routing-ID | Fair-queue | Block |
| **CHANNEL** | Exclusive 1-to-1 | Exclusive 1-to-1 | Block |

## CLI

Install [omq-cli](https://github.com/paddor/omq-cli) for a command-line tool that sends, receives, pipes, and transforms ZeroMQ messages from the terminal:

```sh
gem install omq-cli

omq rep -b tcp://:5555 --echo
echo "hello" | omq req -c tcp://localhost:5555
```

See the [omq-cli README](https://github.com/paddor/omq-cli) for full documentation.

## Companion Gems

- **[omq-ffi](https://github.com/paddor/omq-ffi)** — libzmq FFI backend. Same OMQ socket API, but backed by libzmq instead of the pure Ruby ZMTP stack. Useful for interop testing and when you need libzmq-specific features. Requires libzmq installed.
- **[omq-ractor](https://github.com/paddor/omq-ractor)** — bridge OMQ sockets into Ruby Ractors for true parallel processing across cores. I/O stays on the main Ractor, worker Ractors do pure computation.

## Development

```sh
bundle install
bundle exec rake
```

### Full development setup

Set `OMQ_DEV=1` to tell Bundler to load sibling projects from source
(protocol-zmtp, nuckle, omq-rfc-\*, etc.) instead of released gems.
This is required for running benchmarks and for testing changes across
the stack.

```sh
# clone OMQ and its sibling repos into the same parent directory
git clone https://github.com/paddor/omq.git
git clone https://github.com/paddor/protocol-zmtp.git
git clone https://github.com/paddor/nuckle.git
git clone https://github.com/paddor/omq-rfc-blake3zmq.git
git clone https://github.com/paddor/omq-rfc-channel.git
git clone https://github.com/paddor/omq-rfc-clientserver.git
git clone https://github.com/paddor/omq-rfc-p2p.git
git clone https://github.com/paddor/omq-rfc-qos.git
git clone https://github.com/paddor/omq-rfc-radiodish.git
git clone https://github.com/paddor/omq-rfc-scattergather.git
git clone https://github.com/paddor/omq-ffi.git
git clone https://github.com/paddor/omq-ractor.git

cd omq
OMQ_DEV=1 bundle install
OMQ_DEV=1 bundle exec rake
```

## License

[ISC](LICENSE)
