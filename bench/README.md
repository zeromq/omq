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
| 64 B | 234k | 49k | 36k |
| 256 B | 229k | 45k | 34k |
| 1024 B | 226k | 43k | 34k |
| 4096 B | 233k | 38k | 32k |

## Latency (req/rep roundtrip)

```
┌─────┐  req   ┌─────┐
│ REQ │───────→│ REP │
│     │←───────│     │
└─────┘  rep   └─────┘
```

| | inproc | ipc | tcp |
|---|---|---|---|
| roundtrip | 12 µs | 51 µs | 62 µs |

## REQ/REP throughput (64 B)

| inproc | ipc | tcp |
|---|---|---|
| 88k | 19k | 15k |

## Broker (ROUTER-DEALER, inproc, 4 workers)

| | roundtrip/s |
|---|---|
| broker | 43k |

## io_uring

With `liburing-dev` installed, io-event uses io_uring instead of epoll.
Inproc throughput jumps significantly. IPC and TCP are within variance.

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
| ipc | 239k |
| tcp | 223k |

### PUB/SUB fan-out

| Transport | 1 sub | 5 subs | 10 subs |
|-----------|-------|--------|---------|
| ipc | 209k | 49k | 25k |
| tcp | 210k | 47k | 19k |

## Pipeline (CLI fib benchmark)

```
+----------+     +--------+     +------+
| producer |-IPC-| worker |-IPC-| sink |
| PUSH     |     | pipe×4 |     | PULL |
+----------+     +--------+     +------+
```

### Light work: 1M messages, fib(1..20)

| Mode | msg/s | Time |
|------|------:|-----:|
| Multi-process (4 pipes) | 50,471 | 19.8s |
| Ractors (-P 4)          |  9,635 | 103.8s |

### Heavy work: 10k messages, fib(1..29)

| Mode | msg/s | Time |
|------|------:|-----:|
| Multi-process (4 pipes) | 1,418 | 7.1s |
| Ractors (-P 4)          | 1,739 | 5.7s |

Ractors overtake multi-process when per-message CPU work dominates IPC overhead.

## Running

```sh
ruby --yjit bench/throughput.rb
ruby --yjit bench/latency.rb
ruby --yjit bench/reqrep_throughput/bench.rb
ruby --yjit bench/broker/bench.rb
ruby --yjit bench/flush_batching/bench.rb
sh bench/cli/fib_pipeline/pipeline.sh 1000000 20
sh bench/cli/fib_pipeline/pipeline_ractors.sh 1000000 20 4
```
