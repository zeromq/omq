# Changelog

## 0.4.2 — 2026-03-27

### Fixed

- Send pump dies permanently on connection loss — `rescue` was outside
  the loop, so a single `CONNECTION_LOST` killed the pump and all
  subsequent messages queued but never sent
- NULL handshake deadlocks with buffered IO — missing `io.flush` after
  greeting and READY writes caused both peers to block on read
- Inproc DirectPipe drops messages when send pump runs before
  `direct_recv_queue` is wired — now buffers to `@pending_direct` and
  drains on assignment
- HWM and timeout options set after construction had no effect because
  `Async::LimitedQueue` was already allocated with the default

### Added

- `send_hwm:`, `send_timeout:` constructor kwargs for `PUSH`
- `recv_hwm:`, `recv_timeout:` constructor kwargs for `PULL`

### Changed

- Use `Async::Clock.now` instead of `Process.clock_gettime` internally

## 0.4.1 — 2026-03-27

### Improved

- Explicit flush after `send_message`/`send_command` instead of
  `minimum_write_size: 0` workaround — enables write buffering
  (multi-frame messages coalesced into fewer syscalls).
  **+68% inproc throughput** (145k → 244k msg/s),
  **-40% inproc latency** (15 → 9 µs)

### Fixed

- Require `async ~> 2.38` for `Promise#wait?` (was `~> 2`)

## 0.4.0 — 2026-03-27

### Added (omqcat)

- `--curve-server` flag — generates ephemeral keypair, prints
  `OMQ_SERVER_KEY=...` to stderr for easy copy-paste
- `--curve-server-key KEY` flag — CURVE client mode from the CLI
- `--echo` flag for REP — explicit echo mode
- REP reads stdin/`-F` as reply source (one line per reply, exits at EOF)
- REP without a reply source now aborts with a helpful error message

### Changed

- CURVE env vars renamed: `OMQ_SERVER_KEY`, `OMQ_SERVER_PUBLIC`,
  `OMQ_SERVER_SECRET` (was `SERVER_KEY`, `SERVER_PUBLIC`, `SERVER_SECRET`)
- REP with `--echo`/`-D`/`-e` serves forever by default (like a server).
  Use `-n 1` for one-shot, `-n` to limit exchanges. Stdin/`-F` replies
  naturally terminate at EOF.

## 0.3.2 — 2026-03-26

### Improved

- Hide the warning about the experimental `IO::Buffer` (used by io-stream)

## 0.3.1 — 2026-03-26

### Improved

- `omqcat --help` responds in ~90ms (was ~470ms) — defer heavy gem loading
  until after option parsing

## 0.3.0 — 2026-03-26

### Added

- `omqcat` CLI tool — nngcat-like Swiss army knife for OMQ sockets
  - Socket types: req, rep, pub, sub, push, pull, pair, dealer, router
  - Formats: ascii (default, tab-separated), quoted, raw, jsonl, msgpack
  - `-e` / `--eval` — Ruby code runs inside the socket instance
    (`$F` = message parts, full socket API available: `self <<`, `send`,
    `subscribe`, etc.). REP auto-replies with the return value;
    PAIR/DEALER use `self <<` explicitly
  - `-r` / `--require` to load gems for use in `-e`
  - `-z` / `--compress` Zstandard compression per frame (requires `zstd-ruby`)
  - `-D` / `-F` data sources, `-i` interval, `-n` count, `-d` delay
  - CURVE encryption via `SERVER_KEY` / `SERVER_PUBLIC` + `SERVER_SECRET`
    env vars (requires `omq-curve`)
  - `--identity` / `--target` for DEALER/ROUTER patterns
  - `tcp://:PORT` shorthand for `tcp://*:PORT` (no shell glob issues)
  - 22 system tests via `rake test:cli`

## 0.2.2 — 2026-03-26

### Added

- `ØMQ` alias for `OMQ` — because Ruby can

## 0.2.1 — 2026-03-26

### Improved

- Replace `IO::Buffer` with `pack`/`unpack1`/`getbyte`/`byteslice` in
  frame, command, and greeting codecs — up to 68% higher throughput for
  large messages, 21% lower TCP latency

## 0.2.0 — 2026-03-26

### Changed

- `mechanism` option now holds the mechanism instance directly
  (`Mechanism::Null.new` by default). For CURVE, use
  `OMQ::Curve.server(pub, sec)` or `OMQ::Curve.client(pub, sec, server_key: k)`.
- Removed `curve_server`, `curve_server_key`, `curve_public_key`,
  `curve_secret_key`, `curve_authenticator` socket options

## 0.1.1 — 2026-03-26

### Fixed

- Handle `Errno::EPIPE`, `Errno::ECONNRESET`, `Errno::ECONNABORTED`,
  `Errno::EHOSTUNREACH`, `Errno::ENETUNREACH`, `Errno::ENOTCONN`, and
  `IO::Stream::ConnectionResetError` in accept loops, connect, reconnect,
  and recv/send pumps — prevents unhandled exceptions when peers disconnect
  during handshake or become unreachable
- Use `TCPSocket.new` instead of `Socket.tcp` for reliable cross-host
  connections with io-stream

### Changed

- TCP/IPC `#connect` is now non-blocking — returns immediately and
  establishes the connection in the background, like libzmq
- Consolidated connection error handling via `ZMTP::CONNECTION_LOST` and
  `ZMTP::CONNECTION_FAILED` constants
- Removed `connect_timeout` option (no longer needed since connect is
  non-blocking)

## 0.1.0 — 2026-03-25

Initial release. Pure Ruby implementation of ZMTP 3.1 (ZeroMQ) using Async.

### Socket types

- REQ, REP, DEALER, ROUTER
- PUB, SUB, XPUB, XSUB
- PUSH, PULL
- PAIR

### Transports

- TCP (with ephemeral port support and IPv6)
- IPC (Unix domain sockets, including Linux abstract namespace)
- inproc (in-process, lock-free direct pipes)

### Features

- Buffered I/O via io-stream (read-ahead buffering, automatic TCP_NODELAY)
- Heartbeat (PING/PONG) with configurable interval and timeout
- Automatic reconnection with exponential backoff
- Per-socket send/receive HWM (high-water mark)
- Linger on close (drain send queue before closing)
- `max_message_size` enforcement
- Works inside Async reactors or standalone (shared IO thread)
- Optional CURVE encryption via the [omq-curve](https://github.com/zeromq/omq-curve) gem
