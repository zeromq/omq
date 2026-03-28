# Benchmarks

Measured with `benchmark-ips` on Linux x86_64, Ruby 4.0.2 +YJIT (epoll).

## Throughput (push/pull, msg/s)

```
┌──────┐       ┌──────┐
│ PUSH │──────→│ PULL │
└──────┘       └──────┘
```

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 64 B | 216k | 44k | 32k |
| 256 B | 216k | 31k | 31k |
| 1024 B | 225k | 32k | 30k |
| 4096 B | 227k | 28k | 29k |

## Latency (req/rep roundtrip)

```
┌─────┐  req   ┌─────┐
│ REQ │───────→│ REP │
│     │←───────│     │
└─────┘  rep   └─────┘
```

| | inproc | ipc | tcp |
|---|---|---|---|
| roundtrip | 11 µs | 52 µs | 65 µs |

## io_uring

With `liburing-dev` installed, io-event uses io_uring instead of epoll.
Inproc throughput jumps to **~340k msg/s** — a ~40% improvement.
IPC and TCP are within variance.

```sh
# Debian/Ubuntu
sudo apt install liburing-dev
gem pristine io-event
```

## Burst throughput (push/pull and pub/sub, msg/s)

Under burst load (1000-message bursts), the send pump batches writes
before flushing — reducing syscalls from `N_msgs × N_conns` to `N_conns`
per cycle.

### PUSH/PULL

| Transport | msg/s |
|-----------|-------|
| ipc | 160k |
| tcp | 140k |

### PUB/SUB fan-out

| Transport | 1 sub | 5 subs | 10 subs |
|-----------|-------|--------|---------|
| ipc | 165k | 42k | 17k |
| tcp | 156k | 37k | 18k |

## Running

```sh
ruby --yjit bench/throughput.rb
ruby --yjit bench/latency.rb
ruby --yjit bench/flush_batching/bench.rb
```
