# OMQ Design

Pure Ruby ZeroMQ built on [protocol-zmtp](https://github.com/paddor/protocol-zmtp)
(ZMTP 3.1 wire protocol) and the Async ecosystem.

## Why

ZeroMQ is built on a set of hard-won lessons about networked systems.
The "fallacies of distributed computing" (Deutsch/Gosling, 1994) assume
that the network is reliable, latency is zero, bandwidth is infinite,
topology doesn't change, and transport cost is zero. Every ZMQ mechanism
exists to handle the reality that none of this is true:

| Fallacy | ZMQ / OMQ response |
|---|---|
| The network is reliable | Auto-reconnect with backoff; linger drain on close |
| Latency is zero | Async send queues decouple producers from consumers |
| Bandwidth is infinite | High-water marks (HWM) bound queue depth per connection |
| The network is secure | CURVE encryption (via protocol-zmtp, with RbNaCl or Nuckle) |
| Topology doesn't change | Bind/connect separation; peers come and go freely |
| There is one administrator | No broker required; any topology works peer-to-peer |
| Transport cost is zero | Batched writes reduce syscalls; inproc skips the kernel |
| The network is homogeneous | ZMTP is a wire protocol; interop with libzmq, nanomsg, etc. |

OMQ brings all of this to Ruby without C extensions or FFI.

## Layers

```
+----------------------+
|    Application       |  OMQ::PUSH, OMQ::SUB, etc.
+----------------------+
|    Socket            |  send / receive / bind / connect
+----------------------+
|    Engine            |  connection lifecycle, reconnect, linger
+----------------------+
|    Routing           |  PUSH round-robin, PUB fan-out, REQ/REP, ...
+----------------------+
|    Connection        |  ZMTP handshake, heartbeat, framing
+----------------------+
|    Transport         |  TCP, IPC (Unix), inproc (in-process)
+----------------------+
|  io-stream + Async   |  buffered IO, Fiber::Scheduler
+----------------------+
```

## Task tree

A bare `OMQ::PUSH.new` spawns nothing. The first `#bind` or `#connect`
captures the caller's Async parent and lazily creates a
**socket-level `Async::Barrier`** under it. From that point on, every
pump, listener, reconnect loop, and per-connection supervisor lives
under that one barrier, so teardown is a single call -- `barrier.stop`
cascade-cancels every descendant at once. The parent capture is
one-shot: subsequent bind/connect calls reuse the same barrier.

All spawned tasks are **transient** so they don't prevent the reactor
from exiting when user code finishes. The reactor stays alive during
linger because `Socket#close` blocks (inside the user's fiber) until
send queues drain.

```
parent_task                            Async::Task.current, Reactor root,
|                                      or user's parent (bind/connect parent:)
+-- SocketLifecycle#barrier            Async::Barrier -- single cascade handle
    |
    |-- listener accept loops          one per bind endpoint
    |-- mechanism maintenance          CURVE key refresh, etc.
    |-- reconnect loops                one per dialed endpoint
    |
    |-- conn <ep> task                 spawn_connection (handshake + done.wait)
    |-- conn <ep> supervisor           waits on per-conn barrier, runs lost!
    |
    +-- (ConnectionLifecycle#barrier, nested under socket barrier)
        |-- send pump                  per-connection, work-stealing on socket queue
        |-- recv pump                  or reaper for write-only sockets
        |-- heartbeat                  PING/PONG keepalive
        +-- (subscription listener)    PUB/XPUB/RADIO only
```

**Two barriers.** `SocketLifecycle#barrier` is the socket-level cascade
handle -- `Engine#close`/`#stop` call `.stop` on it once and every
descendant unwinds. `ConnectionLifecycle#barrier` is a nested per-connection
barrier (its parent is the socket barrier) so a supervisor can detect
"one of *this* connection's pumps exited" via `@barrier.wait { ... }` and
cascade-cancel only that connection's siblings -- without taking down
peers on other connections.

**Supervisor pattern.** Each connection has a supervisor task spawned
on the *socket* barrier (deliberately not on the per-conn barrier) that
waits for the first pump to finish and runs `lost!` in `ensure`. Placing
the supervisor outside the per-conn barrier avoids the self-stop footgun:
`tear_down!` can safely call `@barrier.stop` on the per-conn barrier
because the current task (the supervisor) is not a member of it. If the
supervisor were inside, stopping the barrier would raise `Async::Cancel`
on itself synchronously and unwind mid-teardown.

**User-provided parents.** `Socket#bind(ep, parent: my_barrier)` and
`Socket#connect(ep, parent: ...)` wire the socket barrier under the
caller's Async parent -- any object responding to `#async`
(`Async::Task`, `Async::Barrier`, `Async::Semaphore`). The whole socket
subtree then participates in the caller's teardown tree: stopping the
caller's barrier cascades through the socket barrier and every pump.
The first bind/connect captures the parent; subsequent calls are no-ops.

**Send pumps are per-connection, queue is per-socket.** Each connection runs
its own send pump fiber that dequeues from the *socket-level* send queue and
writes to its peer. With N live peers, N pumps race to drain the one queue --
work-stealing. A slow peer's pump just stops pulling (blocked on its own
TCP flush); fast peers' pumps keep draining. This naturally biases load
toward whichever consumers are keeping up, which is exactly what PUSH should
do. Fan-out sockets (PUB/RADIO) use a single pump that reads once and writes
to all matching subscribers.

**Reaper tasks.** Write-only sockets (PUSH, SCATTER) have no recv pump.
Instead, a "reaper" task calls `receive_message` which blocks until the peer
disconnects -- the supervisor observes the pump exit and runs `lost!`.
Without the reaper, a dead peer is only detected on the next send.

## Engine lifecycle

```
bind/connect
  |
  v
[accepting / reconnecting]  <---+
  |                             |
  v                             |
connection_made                 |
  |-- handshake (ZMTP 3.1)      |
  |-- start heartbeat           |
  |-- register with routing     |
  +-- start recv pump / reaper  |
  |                             |
  v                             |
[running]                       |
  |                             |
  v                             |
connection_lost ----------------+  (auto-reconnect if enabled)
  |
  v
close
  |-- stop listeners (if connections exist)
  |-- linger: drain send queues (keep listeners if no peers yet)
  |-- stop remaining listeners
  |-- socket barrier.stop  -- cascade-cancels every pump, supervisor,
  |                           reconnect loop, accept loop in one call
  +-- routing.stop
```

**Close vs. stop.** `Socket#close` is the graceful verb: linger drain,
then cascade. `Socket#stop` skips the linger drain and goes straight to
`barrier.stop` -- used when the caller wants an immediate hard stop
(e.g., on signal, or when the caller's own parent barrier is being
stopped and pending sends should be dropped).

**Convergent teardown.** `Socket#close`, `Socket#stop`, and
peer-disconnect (supervisor-driven `lost!`) all funnel into the same
`ConnectionLifecycle#tear_down!` with identical ordering: routing
removal -> connection close -> monitor event -> done-promise resolve ->
per-conn `barrier.stop`. The state guard (`:closed`) makes it idempotent
so racing pumps can't double-fire side effects.

**Linger.** On close, send queues are drained for up to `linger` seconds.
If no peers are connected, listeners stay open so late-arriving peers can
still receive queued messages. `linger=0` closes immediately.

**Reconnect.** Failed or lost connections are retried with configurable
interval (default 100ms). Supports exponential backoff via a Range
(e.g., `0.1..5.0`). Suppressed once `@state` moves to `:closing`.

## Per-socket HWM (not per-connection)

The send queue is **one per socket**, not one per connection. `send_hwm`
bounds that single queue. This is a deliberate divergence from libzmq, which
gives each pipe its own HWM.

OMQ tried per-pipe HWM briefly. It bought:

- libzmq compatibility on the meaning of `send_hwm`
- Per-peer fairness for sockets where you actively want it (rare)

And it cost:

- A `StagingQueue` to hold messages enqueued before any peer connects
- A drain step (twice, to close a race) every time a peer joins
- A re-staging path on disconnect that prepended a per-conn queue's tail
  back onto staging -- pretending to preserve an ordering guarantee that
  PUSH does not actually have
- Effective buffering of `send_hwm * (N_peers + 1)`, contradicting the
  option's name
- A second concurrency hazard around the connect/disconnect race
- A separate code path for inproc DirectPipe alongside staging and per-conn
  queues

The simpler model -- one shared queue, N work-stealing pumps -- gives:

- **Better PUSH semantics.** Strict per-pipe round-robin is a known libzmq
  footgun ("one slow worker stalls the pipeline"). Work-stealing routes
  messages to whichever consumer is ready, which is what a load balancer
  should do. **User-visible consequence under bursts:** distribution is
  not strict round-robin. If a producer enqueues a burst before any pump
  fiber is scheduled, the first pump to wake dequeues up to one whole
  batch (`BATCH_MSG_CAP` messages or `BATCH_BYTE_CAP` bytes, whichever
  hits first) in a single non-blocking drain — so a tight
  `n.times { sock << msg }` loop with small `n` may dump everything on
  one peer. Slow or steady producers don't see this: each pump dequeues
  one message, writes, re-parks at the back of the FIFO wait queue,
  and the next enqueue wakes the next pump. Burst distribution evens
  out once the burst exceeds one pump's batch cap. This applies to
  every work-stealing routing strategy (PUSH, SCATTER, DEALER, REQ,
  PAIR, CLIENT, CHANNEL).
- **Honest HWM accounting.** `send_hwm = 1000` means 1000 messages, not
  1000 per peer.
- **No staging.** Messages enqueued before any peer connects sit in the
  one queue; the first pump that spawns drains them. No race, no double
  drain, no `prepend`.
- **No ordering pretense.** PUSH has no cross-peer ordering guarantee
  anyway (round-robin interleaves), so on disconnect the in-flight batch
  is simply dropped -- matching libzmq's actual behavior.
- **Same fairness.** Per-pump batch caps (in `drain_send_queue`) and the
  recv-pump 64-msg/1-MB yield limit already give cooperative fairness at
  the fiber level. Per-pipe HWM was not buying anything on top.
- **Same parallelism.** Parallelism comes from N pumps, not N queues.

**The conceptual model:** a ZMQ socket is one networked queue. Peers come
and go; the queue persists. Per-pipe HWM was a leak of libzmq's pipe
implementation into the user-facing semantics. OMQ does not need it.

The single concession: if a pump dequeues a message and its peer dies
before the write completes, the in-flight batch is dropped. This matches
libzmq (which drops on `pipe_terminated`) and is the only honest answer
given the lack of an end-to-end ack at the ZMTP layer. Apps that need
delivery guarantees layer them on top -- REQ/REP, Majordomo, etc.

## Send pump batching

The send pump reduces syscalls by batching:

```
1. Blocking dequeue (wait for first message)
2. Non-blocking drain of all remaining queued messages
3. Write batch to connections (buffered, no flush)
4. Flush each connection once
```

Under light load, batch size is 1 -- no overhead. Under burst load (producer
faster than consumer), the batch grows and flushes are amortized:
`N_msgs * N_conns` syscalls become `N_conns` per cycle.

io-stream auto-flushes its write buffer at 64 KB, so large batches hit the
wire naturally during the write loop. The explicit flush at the end only
pushes the remainder that didn't fill a buffer.

For fan-out (PUB/RADIO), one published message is written to all matching
subscribers before flushing -- so N subscribers see 1 flush each, not N
flushes per message.

## Cancellation safety

The `barrier.stop` cascade can deliver `Async::Cancel` to a send-pump
fiber at any await point. The unencrypted ZMTP path issues two
separate `@io.write` calls per frame (header, then body), so a cancel
arriving between them would leave the peer's framer reading a body
that never arrives -- unrecoverable without closing the connection.

`Protocol::ZMTP::Connection` wraps every wire-write entry point
(`send_message`, `write_message`, `write_messages`, `write_wire`,
`send_command`) in `Async::Task#defer_cancel`. Cancellation requested
during a write is held until the block exits at a frame boundary, then
re-raised normally. The mechanism is orthogonal to the connection's
internal `Mutex` -- the mutex serializes thread races, `defer_cancel`
serializes fiber cancellations. Both are required.

`defer_cancel` only delays cancellation arriving from outside the
block. Exceptions raised by the write itself (`EPIPE`, `EOFError`,
`ECONNRESET`) propagate immediately -- that's the peer-disconnect
path the supervisor relies on.

## Recv pump fairness

Each connection gets its own recv pump fiber that reads messages and
enqueues them into the routing strategy's shared recv queue. Without
bounds, a fast connection could spin its pump indefinitely (io-stream
buffer always has data, recv queue never full), starving slower peers.

The recv pump yields to the fiber scheduler after reading 64 messages or
1 MB from one connection, whichever comes first. This guarantees other
connections' pumps get a turn, regardless of message size or producer
speed. Per-connection message ordering is preserved.

## Transports

**TCP** -- standard network sockets. Bind auto-selects port with `:0`.

**IPC** -- Unix domain sockets. Supports file-based paths and Linux abstract
namespace (`ipc://@name`). File sockets are cleaned up on unbind.

**inproc** -- in-process. Two in-memory queues connect a pair of engines --
no ZMTP framing, no kernel. Message parts are frozen strings passed as
Ruby arrays. Subscription commands (PUB/SUB, RADIO/DISH) flow through
separate queues.

All TCP and IPC connections are wrapped in `IO::Stream::Buffered` which
provides `read_exactly(n)` for reading ZMTP frames and buffered writes
for batch flushing.

## Socket types

| Pattern | Send | Receive | Routing |
|---|---|---|---|
| PUSH/PULL | round-robin | fair-queue | load balancing |
| PUB/SUB | fan-out (prefix match) | subscribe filter | publish/subscribe |
| REQ/REP | round-robin + envelope | envelope-based reply | request/reply |
| DEALER/ROUTER | round-robin / identity | fair-queue / identity | async req/rep |
| PAIR | exclusive 1:1 | exclusive 1:1 | bidirectional |
| CLIENT/SERVER | round-robin | identity-based reply | async client/server |
| RADIO/DISH | fan-out (group match) | join filter | group messaging |
| SCATTER/GATHER | round-robin | fair-queue | like PUSH/PULL |
| PEER/CHANNEL | identity-based | fair-queue | peer-to-peer |

XPUB/XSUB are like PUB/SUB but expose subscription events to the application.

## Dependencies

- **async** -- Fiber::Scheduler reactor, tasks, promises, queues
- **io-stream** -- buffered IO wrapper (read_exactly, flush, connection errors)
- **io-event** -- low-level event loop (epoll/io_uring/kqueue)

Optional: **protocol-zmtp CURVE mechanism** with
[nuckle](https://github.com/paddor/nuckle) (pure Ruby) or
[rbnacl](https://github.com/RubyCrypto/rbnacl) (libsodium) for
CURVE encryption.
