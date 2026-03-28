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
| 64 B | 205k | 46k | 33k |
| 256 B | 205k | 40k | 28k |
| 1024 B | 227k | 41k | 28k |
| 4096 B | 211k | 35k | 25k |

## Latency (req/rep roundtrip)

```
┌─────┐  req   ┌─────┐
│ REQ │───────→│ REP │
│     │←───────│     │
└─────┘  rep   └─────┘
```

| | inproc | ipc | tcp |
|---|---|---|---|
| roundtrip | 12 µs | 55 µs | 74 µs |

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
| ipc | 172k |
| tcp | 149k |

### PUB/SUB fan-out

| Transport | 1 sub | 5 subs | 10 subs |
|-----------|-------|--------|---------|
| ipc | 140k | 35k | 22k |
| tcp | 173k | 41k | 19k |

## Running

```sh
ruby --yjit bench/throughput.rb
ruby --yjit bench/latency.rb
ruby --yjit bench/flush_batching/bench.rb
```
