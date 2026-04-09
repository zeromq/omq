# Changelog

## 0.16.1 — 2026-04-09

### Changed

- **Depend on `protocol-zmtp ~> 0.4`.** Picks up the batched
  `Connection#write_messages` used by the work-stealing send pumps and
  the zero-alloc frame-header path on the unencrypted hot send path.

### Fixed

- **PUB/XPUB/RADIO fan-out now honors `on_mute`.** Per-subscriber send queues
  were hardcoded to `:block`, so a slow subscriber would back-pressure the
  publisher despite PUB/XPUB/RADIO defaulting to `on_mute: :drop_newest`.
  Fan-out now builds each subscriber's queue with the socket's `on_mute`
  strategy — slow subscribers silently drop their own messages without
  stalling the publisher or other subscribers.

## 0.16.0 — 2026-04-09

### Changed

- **Consolidate connection lifecycle into `Engine::ConnectionLifecycle`.** One
  object per connection owns the full arc: handshake → ready → closed. Replaces
  the scattered callback pattern where `Engine`, `ConnectionSetup`, and
  `#close_connections_at` each held partial responsibility for registration,
  monitor emission, routing add/remove, and reconnect scheduling. Side-effect
  order (`:handshake_succeeded` before `connection_added`, `connection_removed`
  before `:disconnected`) is now encoded as sequential statements in two
  methods instead of implicit across multiple files. Teardown is idempotent via
  an explicit 4-state transition table — racing pumps can no longer
  double-fire `:disconnected` or double-call `routing.connection_removed`.
  `ConnectionSetup` is absorbed and removed. `ConnectionRecord` collapses away
  — `@connections` now stores lifecycles directly.

- **Consolidate socket-level state into `Engine::SocketLifecycle`.** Six ivars
  (`@state`, `@peer_connected`, `@all_peers_gone`, `@reconnect_enabled`,
  `@parent_task`, `@on_io_thread`) move into one cohesive object with an
  explicit 4-state transition table (`:new → :open → :closing → :closed`).
  `Engine#closed?`, `#peer_connected`, `#all_peers_gone`, `#parent_task`
  remain as delegators — public API unchanged. Parallels
  `ConnectionLifecycle` in naming and shape. Pure refactor, no behavior change.

- **Revert to per-socket HWM with work-stealing send pumps.** One shared
  bounded send queue per socket, drained by N per-connection send pumps
  that race to dequeue. Slow peers' pumps simply stop pulling; fast peers
  absorb the load. Strictly better PUSH semantics than libzmq's strict
  per-pipe round-robin (a known footgun where one slow worker stalls the
  whole pipeline). Removes `StagingQueue`, per-connection queue maps, the
  double-drain race in `add_*`, the disconnect-prepend ordering pretense,
  and the `@cycle` / next-connection machinery. See `DESIGN.md`
  "Per-socket HWM (not per-connection)" for full reasoning.
- **`RoundRobin` batch cap is now dual: 256 messages OR 512 KB**, whichever
  hits first (previously 64 messages). The old cap was too aggressive for
  large messages — with 64 KB payloads it forced a flush every ~4 MB,
  capping multi-peer push_pull throughput at ~50 % of what the network
  could handle. Dual cap lets large-message workloads batch ~8 messages
  per cycle while small-message workloads still yield quickly enough to
  keep other work-stealing pumps fair. push_pull +5–40 % across transports
  and sizes; router_dealer +5–15 %.
- **Send pumps batched under a single mutex.** RoundRobin, ConnSendPump
  and Pair now drain batches through
  `Protocol::ZMTP::Connection#write_messages`, collapsing N lock
  acquire/release pairs into one per batch. The size==1 path still uses
  `send_message` (write+flush in one lock) to avoid an extra round-trip
  at low throughput. push_pull inproc +18–28 %, tcp/ipc flat to +17 %.

### Fixed

- **`disconnect(endpoint)` now emits `:disconnected`** on the monitor queue.
  Previously silent because `close_connections_at` bypassed `connection_lost`.
- **PUSH/PULL round-robin test.** Previously asserted strict 1-msg-per-peer
  distribution — a libzmq-ism OMQ never promised — and was silently
  "passing" with 0 assertions and a 10 s Async-block timeout that masked a
  hang. New test verifies both peers receive nonzero load over TCP.

### Benchmarks

- Report throughput in bytes/s alongside msgs/s.
- Regenerated `bench/README.md` PUSH/PULL and REQ/REP tables: push_pull
  throughput up 5–40 %, req_rep round-trip latency down 5–15 %.

## 0.15.5 — 2026-04-08

- **`max_message_size` now defaults to `nil` (unlimited)** — previous
  default of 1 MiB moved into omq-cli.
- **Benchmark suite: calibration-driven measurement.** Each cell auto-sizes
  `n` from a prime burst + doubling warmup, then runs `ROUNDS=3` timed
  rounds of `ROUND_DURATION=1.0 s` (override via `OMQ_BENCH_TARGET`) and
  reports the fastest. Full suite runs in ~3 min.
- **Benchmark suite: dropped `curve` transport and the `pair` /
  `dealer_dealer` pattern scripts from the default loop.** Files stay in
  place for ad-hoc runs.
- **`bench/push_pull/omq.rb`** now runs `peer_counts: [1, 3]`.
- **`bench/report.rb --update-readme`** regenerates the PUSH/PULL and
  REQ/REP tables in `bench/README.md` from the latest run in
  `results.jsonl`, between `<!-- BEGIN … -->` / `<!-- END … -->` markers.

## 0.15.4 — 2026-04-08

- **Lazy routing initialization** — the routing strategy is now created on
  first use (bind, connect, send, or receive) instead of eagerly in the
  constructor. This allows socket option setters (`send_hwm=`, `recv_hwm=`)
  to take effect before internal queue sizing.
- **Prefetch byte limit** — `dequeue_recv_batch` now stops at 1 MB total,
  not just 64 messages. Prevents large messages from filling the prefetch
  buffer with hundreds of megabytes.
- **Bound staging queue `@head`** — `StagingQueue#prepend` now drops messages
  when at capacity, preventing unbounded growth during reconnect cycles.
- **Bound monitor queue** — `Socket#monitor` uses a `LimitedQueue(64)` instead
  of an unbounded queue, preventing memory growth when verbose monitoring
  can't keep up with message rate.

## 0.15.3 — 2026-04-08

- **Auto-freeze on bind/connect** — `#bind` and `#connect` now call
  `OMQ.freeze_for_ractors!` automatically, freezing `CONNECTION_LOST`,
  `CONNECTION_FAILED`, and `Engine.transports`. This replaces the internal
  `#freeze_error_lists!` method which only froze the error lists.
- **Drop `Ractor.make_shareable`** — `freeze_for_ractors!` now uses plain
  `.freeze` instead of `Ractor.make_shareable`, removing the Ractor
  dependency from the core freeze path.
- **Freeze routing registry** — `freeze_for_ractors!` now freezes
  `Routing.@registry` so draft socket types (SCATTER, GATHER, etc.)
  can be created inside Ractors.

## 0.15.2 — 2026-04-07

- **Add `OMQ.freeze_for_ractors!`** — freezes `CONNECTION_LOST`,
  `CONNECTION_FAILED`, and `Engine.transports` so OMQ sockets can be
  created inside bare Ractors. Call once before spawning Ractors.

## 0.15.0 — 2026-04-07

- **Fix pipe FIFO ordering** — messages from sequential source batches could
  interleave when a connection dropped and reconnected. `FairQueue` now moves
  orphaned per-connection queues to a priority drain list, ensuring all buffered
  messages from a disconnected peer are consumed before any new peer's messages.
- **Fix lost messages on disconnect** — `RoundRobin#remove_round_robin_send_connection`
  now drains the per-connection send queue back to staging before closing it, and
  the send pump re-stages its in-flight batch on `CONNECTION_LOST`. Previously
  messages in the per-connection queue or mid-batch were silently dropped.
- **Fix `next_connection` deadlock** — when the round-robin cycle exhausted with
  connections still present, a new unresolved `Async::Promise` was created
  unconditionally, blocking the sender forever. Now only creates a new promise
  when `@connections` is actually empty.
- **Fix staging drain race** — `add_round_robin_send_connection` now appends to
  `@connections` after draining staging (not before), preventing the pipe loop
  from bypassing staging during drain. A second drain pass catches any message
  that squeezed in during the first.
- **Fix `handshake_succeeded` event ordering** — the monitor event is now emitted
  before `connection_added` (which may yield during drain), so it always appears
  before any `message_sent` events on that connection.
- **Fix send pump `Async::Stop` preventing reconnect** — `remove_round_robin_send_connection`
  no longer calls `task.stop` on the send pump. Instead it closes the queue and
  lets the pump detect nil, avoiding `Async::Stop` propagation that prevented
  `maybe_reconnect` from running.
- **Add `StagingQueue`** — bounded FIFO queue with `#prepend` for re-staging
  failed messages at the front. Replaces raw `Async::LimitedQueue` in
  `RoundRobin` and `Pair` routing strategies.
- **Add `SingleFrame` mixin to core** — moved from 5 duplicate copies across
  RFC gems to `OMQ::SingleFrame`, eliminating method redefinition warnings.
- **Add `SO_SNDBUF` / `SO_RCVBUF` socket options** — `Options#sndbuf` and
  `Options#rcvbuf` set kernel buffer sizes on TCP and IPC sockets (both
  accepted and connected).
- **Add verbose monitor events** — `Socket#monitor(verbose: true)` emits
  `:message_sent` and `:message_received` events via `Engine#emit_verbose_monitor_event`.
  Allocation-free when verbose is off.
- **Add `OMQ::DEBUG` flag** — when `OMQ_DEBUG` is set, transport accept loops
  print unexpected exceptions to stderr.
- **Fix `Pair` re-staging on disconnect** — `Pair#connection_removed` now drains
  the per-connection send queue back to staging, and the send pump re-stages its
  batch on `CONNECTION_LOST`.

## 0.14.1 — 2026-04-07

- **Fix PUSH send queue deadlock on disconnect** — when a peer disconnected
  while a fiber was blocked on a full per-connection send queue (low `send_hwm`),
  the fiber hung forever. Now closes the queue on disconnect, raising
  `ClosedError` which re-routes the message to staging. Also reorders
  `add_round_robin_send_connection` to start the send pump before draining
  staging, preventing deadlock with small queues.
- **Fix reconnect backoff for plain Numeric** — `#next_delay` incorrectly
  doubled the delay even when `reconnect_interval` was a plain Numeric. Now
  only Range triggers exponential backoff; a fixed Numeric returns the same
  interval every retry.
- **Default `reconnect_interval` changed to `0.1..1.0`** — uses exponential
  backoff (100 ms → 1 s cap) by default instead of a fixed 100 ms.
- **Fix per-connection task tree** — recv pump, heartbeat, and reaper tasks
  were spawned under `@parent_task` (socket-level) instead of the connection
  task. When `@parent_task` finished before a late connection completed its
  handshake, `spawn_pump_task` raised `Async::Task::FinishedError`. Now uses
  `Async::Task.current` so per-connection subtasks are children of their
  connection task, matching the DESIGN.md task tree.

## 0.14.0 — 2026-04-07

- **Fix recv pump crash with connection wrappers** — `start_direct` called
  `msg.sum(&:bytesize)` unconditionally, crashing when a `connection_wrapper`
  (e.g. omq-ractor's `MarshalConnection`) returns deserialized Ruby objects.
  Byte counting now uses `conn.instance_of?(Protocol::ZMTP::Connection)` to
  skip non-ZMTP connections (inproc, Ractor bridges).
- Remove TLS transport dependency from Gemfile.
- YARD documentation on all public methods and classes.
- Code style: expand `else X` one-liners, enforce two blank lines between
  methods and constants.
- Benchmarks: add per-run timeout (default 30s, `OMQ_BENCH_TIMEOUT` env var)
  and abort if a group produces no results.

- Add `Engine::Maintenance` — spawns a periodic `Async::Loop.quantized` timer
  that calls the mechanism's `#maintenance` callback (if defined). Enables
  automatic cookie key rotation for CurveZMQ and BLAKE3ZMQ server mechanisms.
- **YJIT: remove redundant `is_a?` guards in recv pump** — the non-transform
  branch no longer type-checks every message; `conn.receive_message` always
  returns `Array<String>`.
- **YJIT: `FanOut#subscribed?` fast path for subscribe-all** — connections
  subscribed to `""` are tracked in a `@subscribe_all` Set, short-circuiting
  the per-message prefix scan with an O(1) lookup.
- **YJIT: remove safe navigation in hot enqueue paths** — `&.enqueue` calls
  in `FanOut#fan_out_enqueue` and `RoundRobin#enqueue_round_robin` replaced
  with direct calls; queues are guaranteed to exist for live connections.
- **Fix PUB/SUB fan-out over inproc and IPC** — restore `respond_to?(:write_wire)`
  guard in `FanOut#start_conn_send_pump` so DirectPipe connections use
  `#write_message` instead of the wire-optimized path. Add `DirectPipe#encrypted?`
  (returns `false`) for the mechanism query.
- **Code audit: never-instantiated classes** — `RecvPump`, `ConnectionSetup`,
  and `Reconnect` refactored from class-method namespaces to proper instances
  that capture shared state. `Heartbeat`, `Maintenance`, and `ConnSendPump`
  changed from classes to modules (single `self.` method, never instantiated).

## 0.13.0

### Changed

- **`Engine` internals: `ConnectionRecord` + lifecycle state** — three parallel
  per-connection ivars (`@connections` Array, `@connection_endpoints`,
  `@connection_promises`) replaced by a single `@connections` Hash keyed by
  connection, with values `ConnectionRecord = Data.define(:endpoint, :done)`.
  `@connected_endpoints` renamed to `@dialed` (`Set`). `@closed`/`@closing`
  booleans replaced by a `@state` symbol (`:open`/`:closing`/`:closed`).
  Net: −4 instance variables.
- **`@connections` in `FanOut`, `Sub`, `XSub` routing strategies changed from
  `Array` to `Set`** — O(1) `#delete` on peer disconnect; semantics already
  required uniqueness.

### Fixed

- **FanOut send queues no longer drop messages** — per-connection send queues in
  `FanOut` (PUB/XPUB/RADIO) used `DropQueue` (`Thread::SizedQueue`) which never
  blocked the publisher fiber. When burst-sending beyond `send_hwm`, the sender
  ran without yielding and messages were silently dropped. Switched to
  `Async::LimitedQueue` (`:block`) so the publisher yields when a per-connection
  queue is full, giving the send pump fiber a chance to drain it.

### Changed

- **Benchmark suite redesign** — replaced ASCII plots (unicode_plot) with JSONL
  result storage and a colored terminal regression report. Results are appended
  to `bench/results.jsonl` (gitignored, machine-local). New commands:
  `ruby bench/run_all.rb` (run all patterns), `ruby bench/report.rb` (compare
  last runs, highlight regressions/improvements).

### Added

- **Per-peer HWM** — send and receive high-water marks now apply per connected
  peer (RFC 28/29/30). Each peer gets its own bounded send queue and its own
  bounded recv queue. A slow or muted peer no longer steals capacity from
  other peers. `FairQueue` + `SignalingQueue` aggregate per-connection recv
  queues with fair round-robin delivery; `RoundRobin` and `FanOut` mixins
  maintain per-connection send queues with dedicated send pump fibers.
  `PUSH`/`DEALER`/`PAIR` buffer messages in a staging queue when no peers are
  connected yet, draining into the first peer's queue on connect.
- **`FairQueue`** — new aggregator class (`lib/omq/routing/fair_queue.rb`)
  that fair-queues across per-connection bounded queues. Pending messages from
  a disconnected peer are drained before the queue is discarded.
- **`Socket.bind` / `Socket.connect` class-method fix** — now pass the
  endpoint via `@`/`>` prefix into the constructor so any post-attach
  initialization in subclasses (e.g. XSUB's `subscribe:` kwarg) runs after
  the connection is established.



- **QoS infrastructure** — `Options#qos` attribute (default 0) and inproc
  command queue support for QoS-enabled connections. The
  [omq-qos](https://github.com/paddor/omq-qos) gem activates delivery
  guarantees via prepends.
- **REQ send/recv ordering** — REQ sockets now enforce strict
  send/recv/send/recv alternation. Calling `#send` twice without a
  `#receive` in between raises `SocketError`.
- **DirectPipe command frame support** — `DirectPipe#receive_message`
  accepts a block for command frames, matching the `Protocol::ZMTP::Connection`
  interface. Enables inproc transports to handle ACK/NACK and other
  command-level protocols.

### Fixed

- **`send_pump_idle?` visibility** — moved above `private` in `RoundRobin`
  and `FanOut` so `Engine#drain_send_queues` can call it during socket close.

- **`Socket#monitor`** — observe connection lifecycle events via a
  block-based API. Returns an `Async::Task` that yields `MonitorEvent`
  (Data.define) instances for `:listening`, `:accepted`, `:connected`,
  `:connect_delayed`, `:connect_retried`, `:handshake_succeeded`,
  `:handshake_failed`, `:accept_failed`, `:bind_failed`, `:disconnected`,
  `:closed`, and `:monitor_stopped`. Event types align with libzmq's
  `zmq_socket_monitor` where applicable. Pattern-matchable, zero overhead
  when no monitor is attached.
- **Pluggable transport registry** — `Engine.transports` is a scheme →
  module hash. Built-in transports (`tcp`, `ipc`, `inproc`) are registered
  at load time. External gems register via
  `OMQ::Engine.transports["scheme"] = MyTransport`. Each transport
  implements `.bind(endpoint, engine)` → Listener, `.connect(endpoint,
  engine)`, and optionally `.validate_endpoint!(endpoint)`. Listeners
  implement `#start_accept_loops(parent_task, &on_accepted)`, `#stop`,
  `#endpoint`, and optionally `#port`.
- **Mutable error lists** — `CONNECTION_LOST` and `CONNECTION_FAILED` are
  no longer frozen at load time. Transport plugins can append error classes
  (e.g. `OpenSSL::SSL::SSLError`) before the first `#bind`/`#connect`,
  which freezes both arrays.

- **`on_mute` option** — controls behavior when a socket enters the mute state
  (HWM full). PUB, XPUB, and RADIO default to `on_mute: :drop_newest` — slow
  subscribers are skipped in the fan-out rather than blocking the publisher.
  SUB, XSUB, and DISH accept `on_mute: :drop_newest` or `:drop_oldest` to
  drop messages on the receive side instead of applying backpressure. All other
  socket types default to `:block` (existing behavior).
- **`DropQueue`** — bounded queue with `:drop_newest` (tail drop) and
  `:drop_oldest` (head drop) strategies. Used by recv queues when `on_mute`
  is a drop strategy.
- **`Routing.build_queue`** — factory method for building send/recv queues
  based on HWM and mute strategy. Supports HWM of `0` or `nil` for unbounded
  queues.

### Changed

- **`max_message_size` defaults to 1 MiB** — frames exceeding this limit cause
  the connection to be dropped before the body is read from the wire, preventing
  a malicious peer from causing arbitrary memory allocation. Set `socket.max_message_size = nil`
  to restore the previous unlimited behavior.
- **Accept loops moved into Listeners** — `TCP::Listener` and
  `IPC::Listener` now own their accept loop logic via
  `#start_accept_loops(parent_task, &on_accepted)`. Engine delegates
  via duck-type check. This enables external transports to define
  custom accept behavior without modifying Engine.
- `Engine#transport_for` uses registry lookup instead of `case/when`.
- `Engine#validate_endpoint!` delegates to transport module.
- `Engine#bind` reads `listener.port` instead of parsing the endpoint
  string.

### Removed

- **Draft socket types extracted** — `RADIO`, `DISH`, `CLIENT`, `SERVER`,
  `SCATTER`, `GATHER`, `CHANNEL`, and `PEER` are no longer bundled with `omq`.
  Use the [omq-draft](https://github.com/paddor/omq-draft) gem and require
  the relevant entry point (`omq/draft/radiodish`, `omq/draft/clientserver`,
  etc.).
- **UDP transport extracted** — `udp://` endpoints are provided by
  `omq-draft` (via `require "omq/draft/radiodish"`). No longer registered by
  default.
- **`Routing.for` plugin registry** — draft socket type removal added
  `Routing.register(socket_type, strategy_class)` for external gems to
  register routing strategies. Unknown types fall through the built-in
  `case` to this registry before raising `ArgumentError`.

- **TLS transport** — extracted to the
  [omq-transport-tls](https://github.com/paddor/omq-transport-tls) gem.
  (Experimental) `require "omq/transport/tls"` to restore `tls+tcp://` support.
- `tls_context` / `tls_context=` removed from `Options` and `Socket`
  (provided by omq-transport-tls).
- `OpenSSL::SSL::SSLError` removed from `CONNECTION_LOST` (added back
  by omq-transport-tls).
- TLS benchmark transport removed from `bench_helper.rb` and `plot.rb`.

## 0.11.0

### Added

- **`backend:` kwarg** — all socket types accept `backend: :ffi` to use
  the libzmq FFI backend (via the [omq-ffi](https://github.com/paddor/omq-ffi)
  gem). Default is `:ruby` (pure Ruby ZMTP). Enables interop testing and
  access to libzmq-specific features without changing the socket API.
- **TLS transport (`tls+tcp://`)** — TLS v1.3 on top of TCP using Ruby's
  stdlib `openssl`. Set `socket.tls_context` to an `OpenSSL::SSL::SSLContext`
  before bind/connect. Per-socket (not per-endpoint), frozen on first use.
  SNI set automatically from the endpoint hostname. Bad TLS handshakes are
  dropped without killing the accept loop. `OpenSSL::SSL::SSLError` added
  to `CONNECTION_LOST` for automatic reconnection on TLS failures.
  Accompanied by a draft RFC (`rfc/zmtp-tls.md`) defining the transport
  mapping for ZMTP 3.1 over TLS.
- **PUB/RADIO fan-out pre-encoding** — ZMTP frames are encoded once per
  message and written as raw wire bytes to all non-CURVE subscribers.
  Eliminates redundant `Frame.new` + `#to_wire` calls during fan-out.
  CURVE connections (which encrypt at the ZMTP level) still encode
  per-connection. TLS, NULL, and PLAIN all benefit since TLS encrypts
  below ZMTP. Requires protocol-zmtp `Frame.encode_message` and
  `Connection#write_wire`.
- **CURVE benchmarks** — all per-pattern benchmarks now include CURVE
  (via rbnacl) alongside inproc, ipc, tcp, and tls transports.
- **Engine `connection_wrapper` hook** — optional proc on Engine that wraps
  new connections (both inproc and tcp/ipc) at creation time. Used by the
  omq-ractor gem for per-connection serialization (Marshal for tcp/ipc,
  `Ractor.make_shareable` for inproc).
- **Queue-style interface** — readable sockets gain `#dequeue(timeout:)`,
  `#pop`, `#wait`, and `#each`; writable sockets gain `#enqueue` and
  `#push`. Inspired by `Async::Queue`. `#wait` blocks indefinitely
  (ignores `read_timeout`); `#each` returns gracefully on timeout.
- **Recv pump fairness** — each connection yields to the fiber scheduler
  after 64 messages or 1 MB (whichever comes first). Prevents a fast or
  large-message connection from starving slower peers when the consumer
  keeps up. Byte counting gracefully handles non-string messages (e.g.
  deserialized objects from connection wrappers).
- **Per-pattern benchmark suite** — `bench/{push_pull,req_rep,router_dealer,dealer_dealer,pub_sub,pair}/omq.rb`
  with shared helpers (`bench_helper.rb`) and UnicodePlot braille line
  charts (`plot.rb`). Each benchmark measures throughput (msg/s) and
  bandwidth (MB/s) across transports (inproc, ipc, tcp, tls, curve),
  message sizes (64 B–64 KB), and peer counts (1, 3). Plots are written to per-directory
  `README.md` files for easy diffing across versions.

### Changed

- **SUB/XSUB `prefix:` kwarg renamed to `subscribe:`** — aligns with
  ZeroMQ conventions. `subscribe: nil` (no subscription) remains the
  default; pass `subscribe: ''` to subscribe to everything, or
  `subscribe: 'topic.'` for a prefix filter.
- **Scenario benchmarks moved to `bench/scenarios/`** — broker,
  draft_types, flush_batching, hwm_backpressure, large_messages,
  multiframe, pubsub_fanout, ractors_vs_async, ractors_vs_fork,
  reconnect_storm, and reqrep_throughput moved from `bench/` top level.

### Removed

- **Old flat benchmarks** — `bench/throughput.rb`, `bench/latency.rb`,
  `bench/pipeline_mbps.rb`, `bench/run_all.sh` replaced by per-pattern
  benchmarks.
- **`bench/cli/`** — CLI-specific benchmarks (fib pipeline, latency,
  throughput shell scripts) moved to the omq-cli repository.

## 0.10.0 — 2026-04-01

### Added

- **Auto-close sockets via Async task tree** — all engine tasks (accept
  loops, connection tasks, send/recv pumps, heartbeats, reconnect loops,
  reapers) now live under the caller's Async task. When the `Async` block
  exits, tasks are stopped and `ensure` blocks close IO resources.
  Explicit `Socket#close` is no longer required (but remains available
  and idempotent).
- **Non-Async usage** — sockets work outside `Async do…end`. A shared IO
  thread hosts the task tree; all blocking operations (bind, connect,
  send, receive, close) are dispatched to it transparently via
  `Reactor.run`. The IO thread shuts down cleanly at process exit,
  respecting the longest linger across all sockets.
- **Recv prefetching** — `#receive` internally drains up to 64 messages
  per queue dequeue, buffering the excess behind a Mutex. Subsequent
  calls return from the buffer without touching the queue. Thread-safe
  on JRuby. TCP 64B pipelined: 30k → 221k msg/s (7x).

### Changed

- **Transports are pure IO** — TCP and IPC transports no longer spawn
  tasks. They create server sockets and return them; Engine owns the
  accept loops.
- **Reactor simplified** — `spawn_pump` and `PumpHandle` removed.
  Reactor exposes `root_task` (shared IO thread's root Async task)
  and `run` (cross-thread dispatch). `stop!` respects max linger.
- **Flatten `OMQ::ZMTP` namespace into `OMQ`** — with the ZMTP protocol
  layer extracted to `protocol-zmtp`, the `ZMTP` sub-namespace no longer
  makes sense. Engine, routing, transport, and mixins now live directly
  under `OMQ::`. Protocol-zmtp types are referenced as `Protocol::ZMTP::*`.

### Performance

- **Direct pipe bypass for single-peer inproc** — PAIR, CHANNEL, and
  single-peer RoundRobin types (PUSH, REQ, DEALER, CLIENT, SCATTER)
  enqueue directly into the receiver's recv queue, skipping the
  send_queue and send pump entirely.
  Inproc PUSH/PULL: 200k → 980k msg/s (5x).
- **Uncapped send queue drain** — the send pump drains the entire queue
  per cycle instead of capping at 64 messages. IO::Stream auto-flushes
  at 64 KB, so writes hit the wire naturally under load.
  IPC latency −12%, TCP latency −10%.
- **Remove `.b` allocations from PUB/SUB subscription matching** —
  `FanOut#subscribed?` no longer creates temporary binary strings per
  comparison; both topic and prefix are guaranteed binary at rest.
- **Reuse `written` Set and `latest` Hash across batches** in all send
  pumps (fan-out, round-robin, router, server, peer, rep, radio),
  eliminating per-batch object allocation.
- **O(1) `connection_removed` for identity-routed sockets** — Router,
  Server, and Peer now maintain a reverse index instead of scanning.
- **`freeze_message` fast path** — skip `.b.freeze` when the string is
  already a frozen binary string.
- **Pre-frozen empty frame constants** for REQ/REP delimiter frames.

### Fixed

- **Reapers no longer crash on inproc DirectPipe** — PUSH and SCATTER
  reapers skipped for DirectPipe connections that have no receive queue
  (latent bug previously masked by transient task error swallowing).
- **`send_pump_idle?` made public** on all routing strategies — was
  accidentally private, crashing `Engine#drain_send_queues` with
  linger > 0.

## 0.9.0 — 2026-03-31

### Breaking

- **CLI extracted into omq-cli gem** — the `omq` executable, all CLI
  code (`lib/omq/cli/`), tests, and `CLI.md` have moved to the
  [omq-cli](https://github.com/paddor/omq-cli) gem. `gem install omq`
  no longer provides the `omq` command — use `gem install omq-cli`.
- **`OMQ.outgoing` / `OMQ.incoming`** registration API moved to omq-cli.
  Library-only users are unaffected (these were CLI-specific).

### Changed

- **Gemspec is library-only** — no `exe/`, no `bindir`, no `executables`.
- **README** — restored title, replaced inline CLI section with a
  pointer to omq-cli, fixed ZMTP attribution for protocol-zmtp.
- **DESIGN.md** — acknowledged protocol-zmtp, clarified transient
  task / linger interaction, removed ZMTP wire protocol section (now in
  protocol-zmtp), simplified inproc description, removed CLI section.

## 0.8.0 — 2026-03-31

### Breaking

- **CURVE mechanism moved to protocol-zmtp** — `OMQ::ZMTP::Mechanism::Curve`
  is now `Protocol::ZMTP::Mechanism::Curve` with a required `crypto:` parameter.
  Pass `crypto: RbNaCl` (libsodium) or `crypto: Nuckle` (pure Ruby). The
  omq-curve and omq-kurve gems are superseded.

  ```ruby
  # Before (omq-curve)
  require "omq/curve"
  rep.mechanism = OMQ::Curve.server(pub, sec)

  # After (protocol-zmtp + any NaCl backend)
  require "protocol/zmtp/mechanism/curve"
  require "nuckle"  # or: require "rbnacl"
  rep.mechanism = Protocol::ZMTP::Mechanism::Curve.server(pub, sec, crypto: Nuckle)
  ```

### Changed

- **Protocol layer extracted into protocol-zmtp gem** — Codec (Frame,
  Greeting, Command), Connection, Mechanism::Null, Mechanism::Curve,
  ValidPeers, and Z85 now live in the
  [protocol-zmtp](https://github.com/paddor/protocol-zmtp) gem. OMQ
  re-exports them under `OMQ::ZMTP::` for backwards compatibility.
  protocol-zmtp has zero runtime dependencies.
- **Unified CURVE mechanism** — one implementation with a pluggable
  `crypto:` backend replaces the two near-identical copies in omq-curve
  (RbNaCl) and omq-kurve (Nuckle). 1,088 → 467 lines (57% reduction).
- **Heartbeat ownership** — `Connection#start_heartbeat` removed.
  Connection tracks timestamps only; the engine drives the PING/PONG loop.
- **CI no longer needs libsodium** — CURVE tests use
  [nuckle](https://github.com/paddor/nuckle) (pure Ruby) by default.
  Cross-backend interop tests run when rbnacl is available.

## 0.7.0 — 2026-03-30

### Breaking

- **`-e` is now `--recv-eval`** — evaluates incoming messages only.
  Send-only sockets (PUSH, PUB, SCATTER, RADIO) must use `-E` /
  `--send-eval` instead of `-e`.

### Added

- **`-E` / `--send-eval`** — eval Ruby for each outgoing message.
  REQ can now transform requests independently from replies.
  ROUTER/SERVER/PEER: `-E` does dynamic routing (first element =
  identity), mutually exclusive with `--target`.
- **`OMQ.outgoing` / `OMQ.incoming`** — registration API for script
  handlers loaded via `-r`. Blocks receive message parts as a block
  argument (`|msg|`). Setup via closures, teardown via `at_exit`.
  CLI flags override registered handlers.
- **[CLI.md](CLI.md)** — comprehensive CLI documentation.
- **[GETTING_STARTED.md](GETTING_STARTED.md)** — renamed from
  `ZGUIDE_SUMMARY.md` for discoverability.
- **Multi-peer pipe with `--in`/`--out`** — modal switches that assign
  subsequent `-b`/`-c` to the PULL (input) or PUSH (output) side.
  Enables fan-in, fan-out, and mixed bind/connect per side.
  Backward compatible — without `--in`/`--out`, the positional
  2-endpoint syntax works as before.

### Improved

- **YJIT recv pump** — replaced lambda/proc `transform:` parameter in
  `Engine#start_recv_pump` with block captures. No-transform path
  (PUSH/PULL, PUB/SUB) is now branch-free. ~2.5x YJIT speedup on
  inproc, ~2x on ipc/tcp.

### Fixed

- **Frozen array from `recv_msg_raw`** — ROUTER/SERVER receiver crashed
  with `FrozenError` when shifting identity off frozen message arrays.
  `#recv_msg_raw` now dups the array.

## 0.6.5 — 2026-03-30

### Fixed

- **CLI error path** — use `Kernel#exit` instead of `Process.exit!`

## 0.6.4 — 2026-03-30

### Added

- **Dual-stack TCP bind** — `TCP.bind` resolves the hostname via
  `Addrinfo.getaddrinfo` and binds to all returned addresses.
  `tcp://localhost:PORT` now listens on both `127.0.0.1` and `::1`.
- **Eager DNS validation on connect** — `Engine#connect` resolves TCP
  hostnames upfront via `Addrinfo.getaddrinfo`. Unresolvable hostnames
  raise `Socket::ResolutionError` immediately instead of failing silently
  in the background reconnect loop.
- **`Socket::ResolutionError` in `CONNECTION_FAILED`** — DNS failures
  during reconnect are now retried with backoff (DNS may recover or
  change), matching libzmq behavior.
- **CLI catches `SocketDeadError` and `Socket::ResolutionError`** —
  prints the error and exits with code 1 instead of silently exiting 0.

### Improved

- **CLI endpoint shorthand** — `tcp://:PORT` expands to
  `tcp://localhost:PORT` (loopback, safe default). `tcp://*:PORT` expands
  to `tcp://0.0.0.0:PORT` (all interfaces, explicit opt-in).

### Fixed

- **`tcp://*:PORT` failed on macOS** — `*` is not a resolvable hostname.
  Connects now use `localhost` by default; `*` only expands to `0.0.0.0`
  for explicit all-interface binding.
- **`Socket` constant resolution inside `OMQ` namespace** — bare `Socket`
  resolved to `OMQ::Socket` instead of `::Socket`, causing `NameError`
  for `Socket::ResolutionError` and `Socket::AI_PASSIVE`.

## 0.6.3 — 2026-03-30

### Fixed

- **`self << msg` in REP `-e` caused double-send** — `self << $F`
  returns the socket, which `eval_expr` tried to coerce via `to_str`.
  Now detected via `result.equal?(@sock)` and returned as a `SENT`
  sentinel. REP skips the auto-send when the eval already sent the reply.
- **`eval_expr` called `to_str` on non-string results** — non-string,
  non-array return values from `-e` now fail with a clear `NoMethodError`
  on `to_str` (unchanged), but socket self-references are handled first.

## 0.6.2 — 2026-03-30

### Improved

- **Gemspec summary** — highlights the CLI's composable pipeline
  capabilities (pipe, filter, transform, formats, Ractor parallelism).
- **README CLI section** — added `pipe`, `--transient`, `-P/--parallel`,
  `BEGIN{}/END{}` blocks, `$_` variable, and `--marshal` format.

### Fixed

- **Flaky memory leak tests on CI** — replaced global `ObjectSpace`
  counting with `WeakRef` tracking of specific objects, retrying GC
  until collected. No longer depends on GC generational timing.

## 0.6.1 — 2026-03-30

### Improved

- **`pipe` in CLI help and examples** — added `pipe` to the help banner
  as a virtual socket type (`PULL → eval → PUSH`) and added examples
  showing single-worker, `-P` Ractor, and `--transient` usage.
- **Pipeline benchmarks run from any directory** — `pipeline.sh` and
  `pipeline_ractors.sh` now derive absolute paths from the script
  location instead of assuming the working directory is the project root.

### Fixed

- **Flaky memory leak tests on CI** — replaced global `ObjectSpace`
  counting with `WeakRef` tracking of specific objects, retrying GC
  until collected. No longer depends on GC generational timing.

## 0.6.0 — 2026-03-30

### Added

- **`OMQ::SocketDeadError`** — raised on `#send`/`#receive` after an
  internal pump task crashes. The original exception is available via
  `#cause`. The socket is permanently bricked.
- **`Engine#spawn_pump_task`** — replaces bare `parent_task.async(transient: true)`
  in all 10 routing strategies. Catches unexpected exceptions and forwards
  them via `signal_fatal_error` so blocked `#send`/`#receive` callers see
  the real error instead of deadlocking.
- **`Socket#close_read`** — pushes a nil sentinel into the recv queue,
  causing a blocked `#receive` to return nil. Used by `--transient` to
  drain remaining messages before exit instead of killing the task.
- **`send_pump_idle?`** on all routing classes — tracks whether the send
  pump has an in-flight batch. `Engine#drain_send_queues` now waits for
  both `send_queue.empty?` and `send_pump_idle?`, preventing message loss
  during linger close.
- **Grace period after `peer_connected`** — senders that bind or connect
  to multiple endpoints sleep one `reconnect_interval` (100ms) after the
  first peer handshake, giving latecomers time to connect before messages
  start flowing.
- **`-P/--parallel [N]` for `omq pipe`** — spawns N Ractor workers
  (default: nproc) in a single process for true CPU parallelism. Each
  Ractor runs its own Async reactor with independent PULL/PUSH sockets.
  `$F` in `-e` expressions is transparently rewritten for Ractor isolation.
- **`BEGIN{}`/`END{}` blocks in `-e` expressions** — like awk, run setup
  before the message loop and teardown after. Supports nested braces.
  Example: `-e 'BEGIN{ @sum = 0 } @sum += Integer($_); next END{ puts @sum }'`
- **`--reconnect-ivl`** — set reconnect interval from the CLI, accepts a
  fixed value (`0.5`) or a range for exponential backoff (`0.1..2`).
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
  (`bench/cli/pipeline.sh`). ~300–1800 msg/s depending on N.
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

- **Received messages are always frozen** — `Connection#receive_message`
  (TCP/IPC) now returns a frozen array of frozen strings, matching the
  inproc fast-path. REP and REQ recv transforms rewritten to avoid
  in-place mutation (`Array#shift` → slicing).
- **CLI refactored into 16 files** — the 1162-line `cli.rb` monolith is
  decomposed into `CLI::Config` (frozen `Data.define`), `CLI::Formatter`,
  `CLI::BaseRunner` (shared infrastructure), and one runner class per
  socket type combo (PushRunner, PullRunner, ReqRunner, RepRunner, etc.).
  Each runner models its behavior as a single `#run_loop` override.
- **`--transient` uses `close_read` instead of `task.stop`** — recv-only
  and bidirectional sockets drain their recv queue via nil sentinel before
  exiting, preventing message loss on disconnect. Send-only sockets still
  use `task.stop`.
- **Pipeline benchmark** — natural startup order (producer → workers →
  sink), workers use `--transient -t 1` (timeout covers workers that
  connect after the producer is already gone). Verified correct at 5M messages
  (56k msg/s sustained, zero message loss).
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

- **Inproc DEALER→REP broker deadlock** — `Writable#send` freezes the
  message array, but the REP recv transform mutated it in-place via
  `Array#shift`. On the inproc fast-path the frozen array passed through
  the DEALER send pump unchanged, causing `FrozenError` that silently
  killed the send pump task and deadlocked the broker.
- **Pump errors swallowed silently** — all send/recv pump tasks ran as
  `transient: true` Async tasks, so unexpected exceptions (bugs) were
  logged but never surfaced to the caller. The socket would deadlock
  instead of raising. Now `Engine#signal_fatal_error` stores the error
  and unblocks the recv queue; subsequent `#send`/`#receive` calls
  re-raise it as `SocketDeadError`. Expected errors (`Async::Stop`,
  `ProtocolError`, `CONNECTION_LOST`) are still handled normally.
- **Pipe `--transient` drains too early** — `all_peers_gone` fired while
  `pull.receive` was blocked, hanging the worker forever. Now the transient
  monitor pushes a nil sentinel via `close_read`, which unblocks the
  blocked dequeue and lets the loop drain naturally.
- **Linger drain missed in-flight batches** — `drain_send_queues` only
  checked `send_queue.empty?`, but the send pump may have already dequeued
  messages into a local batch. Now also checks `send_pump_idle?`.
- **Socket option delegators not Ractor-safe** — `define_method` with a
  block captured state from the main Ractor, causing `Ractor::IsolationError`
  when calling setters like `recv_timeout=`. Replaced with `Forwardable`.
- **Pipe endpoint ordering** — `omq pipe -b url1 -c url2` assigned PULL
  to `url2` and PUSH to `url1` (backwards) because connects were
  concatenated before binds. Now uses ordered `Config#endpoints`.
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
- Optional CURVE encryption via the [protocol-zmtp](https://github.com/paddor/protocol-zmtp) gem
