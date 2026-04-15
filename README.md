# ØMQ — ZeroMQ for Ruby, no C required

[![CI](https://github.com/zeromq/omq/actions/workflows/ci.yml/badge.svg)](https://github.com/zeromq/omq/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/omq?color=e9573f)](https://rubygems.org/gems/omq)
[![License: ISC](https://img.shields.io/badge/License-ISC-blue.svg)](LICENSE)
[![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.3-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org)

> **932k msg/s** inproc | **328k msg/s** ipc | **329k msg/s** tcp
>
> **11.5 µs** inproc latency | **54 µs** ipc | **69 µs** tcp
>
> Ruby 4.0 + YJIT on a Linux VM — see [`bench/`](bench/) for full results

`gem install omq` and you're done. No libzmq, no compiler, no system packages —
just Ruby talking to every other ZeroMQ peer out there.

ØMQ gives your Ruby processes a way to talk to each other — and to anything
else speaking ZeroMQ — without a broker in the middle. Same API whether they
live in the same process, on the same machine, or across the network.
Reconnects, queuing, and back-pressure are handled for you; you write the
interesting part.

New to ZeroMQ? Start with [GETTING_STARTED.md](GETTING_STARTED.md) — a ~30 min
walkthrough of every major pattern with working code.

## Highlights

- **Zero dependencies on C** — no extensions, no FFI, no libzmq. `gem install`
  just works everywhere
- **Fast** — YJIT-optimized hot paths, batched sends, GC-tuned allocations,
  buffered I/O via [io-stream](https://github.com/socketry/io-stream),
  direct-pipe inproc bypass
- **[`omq` CLI](https://github.com/paddor/omq-cli)** — a powerful swiss army
  knife for ØMQ. `gem install omq-cli`
- **Every socket pattern** — req/rep, pub/sub, push/pull, dealer/router,
  xpub/xsub, pair, and all draft types
- **Every transport** — tcp, ipc (Unix domain sockets), inproc (in-process
  queues)
- **Async-native** — built on fibers, non-blocking from the ground up
- **Works outside Async too** — a shared IO thread handles sockets for callers
  that aren't inside a reactor, so simple scripts just work
- **Wire-compatible** — interoperates with libzmq, pyzmq, CZMQ, zmq.rs over tcp
  and ipc
- **Bind/connect order doesn't matter** — connect before bind, bind before
  connect, peers come and go. ZeroMQ reconnects automatically and queued
  messages drain when peers arrive

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

OMQ spawns a shared `omq-io` thread when used outside an Async reactor — no
boilerplate needed:

```ruby
require 'omq'

push = OMQ::PUSH.bind('tcp://127.0.0.1:5557')
pull = OMQ::PULL.connect('tcp://127.0.0.1:5557')

push << 'hello'
p pull.receive  # => ["hello"]

push.close
pull.close
```

The IO thread runs all pumps, reconnection, and heartbeating in the background.
When you're inside an `Async` block, OMQ uses the existing reactor instead.

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

All sockets are thread-safe. Default HWM is 1000 messages per socket.
`max_message_size` defaults to **`nil` (unlimited)** — set
`socket.max_message_size = N` to cap inbound frames at `N` bytes; oversized
frames cause the connection to be dropped before the body is read from the
wire. Classes live under `OMQ::` (alias: `ØMQ`).

#### Standard (multipart messages)

| Pattern | Send | Receive | When HWM full |
|---------|------|---------|---------------|
| **REQ** / **REP** | Work-stealing / route-back | Fair-queue | Block |
| **PUB** / **SUB** | Fan-out to subscribers | Subscription filter | Drop |
| **PUSH** / **PULL** | Work-stealing to workers | Fair-queue | Block |
| **DEALER** / **ROUTER** | Work-stealing / identity-route | Fair-queue | Block |
| **XPUB** / **XSUB** | Fan-out (subscription events) | Fair-queue | Drop |
| **PAIR** | Exclusive 1-to-1 | Exclusive 1-to-1 | Block |

> **Work-stealing, not round-robin.** Outbound load balancing uses one shared
> send queue per socket drained by N racing pump fibers, so a slow peer can't
> stall the pipeline. Under tight bursts on small `n`, distribution isn't
> strict RR. See [DESIGN.md](DESIGN.md#per-socket-hwm-not-per-connection) and
> [Libzmq quirks](DESIGN.md#libzmq-quirks-omq-avoids) for the reasoning.

#### Draft (single-frame only)

Each draft pattern lives in its own gem — install only the ones you use.

| Pattern | Send | Receive | When HWM full | Gem |
|---------|------|---------|---------------|-----|
| **CLIENT** / **SERVER** | Work-stealing / routing-ID | Fair-queue | Block | [`omq-rfc-clientserver`](https://github.com/paddor/omq-rfc-clientserver) |
| **RADIO** / **DISH** | Group fan-out | Group filter | Drop | [`omq-rfc-radiodish`](https://github.com/paddor/omq-rfc-radiodish) |
| **SCATTER** / **GATHER** | Work-stealing | Fair-queue | Block | [`omq-rfc-scattergather`](https://github.com/paddor/omq-rfc-scattergather) |
| **PEER** | Routing-ID | Fair-queue | Block | [`omq-rfc-p2p`](https://github.com/paddor/omq-rfc-p2p) |
| **CHANNEL** | Exclusive 1-to-1 | Exclusive 1-to-1 | Block | [`omq-rfc-channel`](https://github.com/paddor/omq-rfc-channel) |

## CLI

Install [omq-cli](https://github.com/paddor/omq-cli) for a command-line tool
that sends, receives, pipes, and transforms ZeroMQ messages from the terminal:

```sh
gem install omq-cli

omq rep -b tcp://:5555 --echo
echo "hello" | omq req -c tcp://localhost:5555
```

See the [omq-cli README](https://github.com/paddor/omq-cli) for full documentation.

## Companion Gems

- **[omq-ffi](https://github.com/paddor/omq-ffi)** — libzmq FFI backend. Same
  OMQ socket API, but backed by libzmq instead of the pure Ruby ZMTP stack.
  Useful for interop testing and when you need libzmq-specific features.
  Requires libzmq installed.
- **[omq-ractor](https://github.com/paddor/omq-ractor)** — bridge OMQ sockets
  into Ruby Ractors for true parallel processing across cores. I/O stays on the
  main Ractor, worker Ractors do pure computation.

### Protocol extensions (RFCs)

Optional plug-ins that extend the ZMTP wire protocol. Each is a separate gem;
load the ones you need.

- **[omq-rfc-zstd](https://github.com/paddor/omq-rfc-zstd)** — transparent
  Zstandard compression on the wire, negotiated per peer via READY properties.

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
git clone https://github.com/paddor/omq-rfc-zstd.git
git clone https://github.com/paddor/omq-rfc-clientserver.git
git clone https://github.com/paddor/omq-rfc-radiodish.git
git clone https://github.com/paddor/omq-rfc-scattergather.git
git clone https://github.com/paddor/omq-rfc-channel.git
git clone https://github.com/paddor/omq-rfc-p2p.git
git clone https://github.com/paddor/omq-rfc-qos.git
git clone https://github.com/paddor/omq-ffi.git
git clone https://github.com/paddor/omq-ractor.git
git clone https://github.com/paddor/nuckle.git

cd omq
OMQ_DEV=1 bundle install
OMQ_DEV=1 bundle exec rake
```

## License

[ISC](LICENSE)
