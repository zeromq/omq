# Changelog

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
- Optional CURVE encryption via the [omq-curve](https://github.com/paddor/omq-curve) gem
