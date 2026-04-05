# Benchmarks

Measured with `benchmark-ips` on Linux x86_64, Ruby 4.0.2 +YJIT (epoll).

## Throughput (PUSH/PULL, msg/s)

```
┌──────┐       ┌──────┐
│ PUSH │──────→│ PULL │
└──────┘       └──────┘
```

### 1 peer (inproc uses direct pipe bypass)

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 64 B | 980k | 38k | 31k |
| 256 B | 775k | 34k | 29k |
| 1024 B | 908k | 30k | 30k |
| 4096 B | 814k | 26k | 27k |

### 3 peers (round-robin via send pump)

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 64 B | 160k | 38k | 31k |
| 256 B | 165k | 39k | 29k |
| 1024 B | 193k | 36k | 29k |
| 4096 B | 165k | 29k | 25k |

## Latency (REQ/REP roundtrip)

```
┌─────┐  req   ┌─────┐
│ REQ │───────→│ REP │
│     │←───────│     │
└─────┘  rep   └─────┘
```

| | inproc | ipc | tcp |
|---|---|---|---|
| 1 peer | 10.5 µs | 71.0 µs | 82.4 µs |
| 3 peers | 10.0 µs | 62.5 µs | 76.4 µs |

## Pipeline throughput (sustained MB/s)

100k messages, sender ahead of receiver (recv prefetch active).

### 1 peer

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 64 B | 49 MB/s | 13 MB/s | 15 MB/s |
| 1 KB | 927 MB/s | 141 MB/s | 148 MB/s |
| 4 KB | 4.7 GB/s | 371 MB/s | 389 MB/s |
| 64 KB | 76 GB/s | 838 MB/s | 885 MB/s |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 64 B | 66 MB/s | 13 MB/s | 15 MB/s |
| 1 KB | 960 MB/s | 142 MB/s | 136 MB/s |
| 4 KB | 4.9 GB/s | 379 MB/s | 392 MB/s |
| 64 KB | 77 GB/s | 921 MB/s | 921 MB/s |

## io_uring

With `liburing-dev` installed, io-event uses io_uring instead of epoll.
Inproc throughput jumps significantly. IPC and TCP are within variance.

```sh
# Debian/Ubuntu
sudo apt install liburing-dev
gem pristine io-event
```

## Running

```sh
# Run full suite (appends to bench/results.jsonl)
ruby --yjit bench/run_all.rb

# Run single pattern
ruby --yjit bench/push_pull/omq.rb

# Regression report (latest vs previous run)
ruby bench/report.rb

# Full comparison table
ruby bench/report.rb --all
```
