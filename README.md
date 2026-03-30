# OMQ — ZeroMQ in pure Ruby

[![CI](https://github.com/zeromq/omq/actions/workflows/ci.yml/badge.svg)](https://github.com/zeromq/omq/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/omq?color=e9573f)](https://rubygems.org/gems/omq)
[![License: ISC](https://img.shields.io/badge/License-ISC-blue.svg)](LICENSE)
[![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.3-CC342D?logo=ruby&logoColor=white)](https://www.ruby-lang.org)

`gem install omq` — that's it. No libzmq, no compiler, no system packages. Just Ruby.

OMQ implements the [ZMTP 3.1](https://rfc.zeromq.org/spec/23/) wire protocol from scratch using [Async](https://github.com/socketry/async) fibers. It speaks native ZeroMQ on the wire and interoperates with libzmq, pyzmq, CZMQ, and everything else in the ZMQ ecosystem.

> **244k msg/s** inproc | **47k msg/s** ipc | **36k msg/s** tcp
>
> **9 µs** inproc latency | **47 µs** ipc | **61 µs** tcp
>
> Ruby 4.0 + YJIT — [~340k msg/s with io_uring](bench/README.md#io_uring)

---

## Highlights

- **Zero dependencies on C** — no extensions, no FFI, no libzmq. `gem install` just works everywhere
- **Fast** — YJIT-optimized hot paths, batched sends, 244k msg/s inproc with single-digit µs latency
- **`omq` CLI** — pipe, filter, and transform messages from the terminal with Ruby eval, Ractor parallelism, and [script handlers](CLI.md#script-handlers--r)
- **Every socket pattern** — req/rep, pub/sub, push/pull, dealer/router, xpub/xsub, pair, and all draft types
- **Every transport** — tcp, ipc (Unix domain sockets), inproc (in-process queues)
- **Async-native** — built on fibers, non-blocking from the ground up

New to ZeroMQ? See [GETTING_STARTED.md](GETTING_STARTED.md) — a ~30 min read covering all major patterns with working OMQ code examples.

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

## Interop

OMQ interoperates with libzmq, CZMQ, pyzmq, etc. over **tcp** and **ipc**. The `inproc://` transport is OMQ-internal (in-process Ruby queues) — use `ipc://` to talk across library boundaries.

## Development

```sh
bundle install
bundle exec rake
```

## License

[ISC](LICENSE)
