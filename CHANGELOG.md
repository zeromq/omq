# Changelog

## 0.6.0 — 2026-03-28

### Added

- **`--transient`** — exit when all peers disconnect (after at least one
  message has been sent/received). Useful for pipeline sinks and workers.
- **`--examples`** — annotated usage examples, paged via `$PAGER` or `less`.
  `--help` now shows help + examples (paged); `-h` shows help only.
- **`-r` relative paths** — `-r./lib.rb` and `-r../lib.rb` resolve via
  `File.expand_path` instead of `$LOAD_PATH`.
- **`peer_connected` / `all_peers_gone`** — `Async::Promise` hooks on
  `Socket` for connection lifecycle tracking.
- **`reconnect_enabled=`** — disable auto-reconnect per socket.
- **Pipeline benchmark** — 4-worker fib pipeline via `omq` CLI
  (`bench/omqcat/pipeline.sh`). ~300–1800 msg/s depending on N.
- **DESIGN.md** — architecture overview covering task trees, send pump
  batching, ZMTP wire protocol, transports, and the fallacies of
  distributed computing.
- **Draft socket types in omqcat** — CLIENT, SERVER, RADIO, DISH, SCATTER,
  GATHER, CHANNEL, and PEER are now supported in the CLI tool.
  - `-j`/`--join GROUP` for DISH (like `--subscribe` for SUB)
  - `-g`/`--group GROUP` for RADIO publishing
  - `--target` extended to SERVER and PEER (accepts `0x` hex for binary routing IDs)
  - `--echo` and `-e` on SERVER/PEER reply to the originating client via `send_to`
  - CLIENT uses request-reply loop (send then receive)
- **Unified `--timeout`** — replaces `--recv-timeout`/`--send-timeout` with a
  single `-t`/`--timeout` flag that applies to both directions.
- **`--linger`** — configurable drain time on close (default 5s).
- **Exit codes** — 0 = success, 1 = error, 2 = timeout.
- **CLI unit tests** — 74 tests covering Formatter, routing helpers,
  validation, and option parsing.
- **Quantized `--interval`** — uses `Async::Loop.quantized` for
  wall-clock-aligned, start-to-start timing (no drift).
- **`-e` as data source** — eval expressions can generate messages without
  `--data`, `--file`, or stdin. E.g. `omq pub -e 'Time.now.to_s' -i 1`.
- **`$_` in eval** — set to the first frame of `$F` inside `-e` expressions,
  following Ruby convention.
- **`wait_for_peer`** — connecting sockets wait for the first peer handshake
  before sending. Replaces the need for manual `--delay` on PUB, PUSH, etc.
- **`OMQ_DEV` env var** — unified dev-mode flag for loading local omq and
  omq-curve source via `require_relative` (replaces `DEV_ENV`).
- **`--marshal` / `-M`** — Ruby Marshal stream format. Sends any Ruby
  object over the wire; receiver deserializes and prints `inspect` output.
  E.g. `omq pub -e 'Time.now' -M` / `omq sub -M`.
- **`-e` single-shot** — eval runs once and exits when no other data
  source is present. Supports `self << msg` for direct socket sends.
- **`subscriber_joined`** — `Async::Promise` on PUB/XPUB that resolves
  when the first subscription arrives. CLI PUB waits for it before sending.
- **`#to_str` enforcement** — message parts must be string-like; passing
  integers or symbols raises `NoMethodError` instead of silently coercing.
- **`-e` error handling** — eval errors abort with exit code 3.
- **`--raw` outputs ZMTP frames** — flags + length + body per frame,
  suitable for `hexdump -C`. Compression remains transparent.
- **ROUTER `router_mandatory` by default** — CLI ROUTER rejects sends to
  unknown identities and waits for first peer before sending.
- **`--timeout` applies to `wait_for_peer`** — `-t` now bounds the initial
  connection wait via `Async::TimeoutError`.

### Improved

- **Renamed `omqcat` → `omq`** — the CLI executable is now `omq`, matching
  the gem name.
- **Per-connection task subtrees** — each connection gets an isolated Async
  task whose children (heartbeat, recv pump, reaper) are cleaned up
  automatically when the connection dies. No reparenting.
- **Flat task tree** — send pump spawned at socket level (singleton), not
  inside connection subtrees. Accept loops use `defer_stop` to prevent
  socket leaks on stop.
- **`compile_expr`** — `-e` expressions compiled once as a proc,
  `instance_exec` per message (was `instance_eval` per message).
- **Close lifecycle** — stop listeners before drain only when connections
  exist; keep listeners open with zero connections so late-arriving peers
  can receive queued messages during linger.
- **Reconnect guard** — `@closing` flag suppresses reconnect during close.
- **Task annotations** — all pump tasks carry descriptive annotations
  (send pump, recv pump, reaper, heartbeat, reconnect, tcp/ipc accept).
- **Rename monitor → reaper** — clearer name for PUSH/SCATTER dead-peer
  detection tasks.
- **Extracted `OMQ::CLI` module** — `exe/omq` is a thin wrapper;
  bulk of the CLI lives in `lib/omq/cli.rb` (loaded via `require "omq/cli"`,
  not auto-loaded by `require "omq"`).
  - `Formatter` class for encode/decode/compress/decompress
  - `Runner` is stateful with `@sock`, cleaner method signatures
- **Quoted format uses `String#dump`/`undump`** — fixes backslash escaping
  bug, proper round-tripping of all byte values.
- **Hex routing IDs** — binary identities display as `0xdeadbeef` instead
  of lossy Z85 encoding. `--target 0x...` decodes hex on input.
- **Compression-safe routing** — routing ID and delimiter frames are no
  longer compressed/decompressed in ROUTER, SERVER, and PEER loops.
- **`require_relative` in CLI** — `exe/omq` loads the local source tree
  instead of the installed gem.
- **`output` skips nil** — `-e` returning nil no longer prints a blank line.
- **Removed `#count_reached?`** — inlined for clarity.
- **System tests overhauled** — `test/omqcat` → `test/cli`, all IPC
  abstract namespace, `set -eu`, stderr captured, no sleeps (except
  ROUTER --target), under 10s.

### Fixed

- **Linger drain kills reconnect tasks** — `Engine#close` set `@closed = true`
  before draining send queues, causing reconnect tasks to bail immediately.
  Messages queued before any peer connected were silently dropped. Now `@closed`
  is set after draining, so reconnection continues during the linger period.

## 0.5.1 — 2026-03-28

### Improved

- **3–4x throughput under burst load** — send pumps now batch writes
  before flushing. `Connection#write_message` buffers without flushing;
  `Connection#flush` triggers the syscall. Pumps drain all queued messages
  per cycle, reducing flush count from `N_msgs × N_conns` to `N_conns`
  per batch. PUB/SUB TCP with 10 subscribers: 2.3k → 9.2k msg/s (**4x**).
  PUSH/PULL TCP: 24k → 83k msg/s (**3.4x**). Zero overhead under light
  load (batch of 1 = same path as before).

- **Simplified Reactor IO thread** — replaced `Thread::Queue` + `IO.pipe`
  wake signal with a single `Async::Queue`. `Thread::Queue#pop` is
  fiber-scheduler-aware in Ruby 4.0, so the pipe pair was unnecessary.

### Fixed

- **`router_mandatory` SocketError raised in send pump** — the error
  killed the pump fiber instead of reaching the caller. Now checked
  synchronously in `enqueue` before queuing.

## 0.5.0 — 2026-03-28

### Added

- **Draft socket types** (RFCs 41, 48, 49, 51, 52):
  - `CLIENT`/`SERVER` — thread-safe REQ/REP without envelope, 4-byte routing IDs
  - `RADIO`/`DISH` — group-based pub/sub with exact match, JOIN/LEAVE commands.
    `radio.publish(group, body)`, `radio.send(body, group:)`, `radio << [group, body]`
  - `SCATTER`/`GATHER` — thread-safe PUSH/PULL
  - `PEER` — bidirectional multi-peer with 4-byte routing IDs
  - `CHANNEL` — thread-safe PAIR
- All draft types enforce single-frame messages (no multipart)
- Reconnect-after-restart tests for all 10 socket type pairings

### Fixed

- **PUSH/SCATTER silently wrote to dead peers** — write-only sockets had
  no recv pump to detect peer disconnection. Writes succeeded because the
  kernel send buffer absorbed the data, preventing reconnect from
  triggering. Added background monitor task per connection.
- **PAIR/CHANNEL stale send pump after reconnect** — old send pump kept
  its captured connection reference and raced with the new send pump,
  sending to the dead connection. Now stopped in `connection_removed`.

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
