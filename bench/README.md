# Benchmarks

Measured in a Linux VM on a 2019 Intel MacBook Pro, Ruby 4.0.2 +YJIT. Each cell
is the fastest of 3 timed rounds (~1 s each) after a calibration warmup, so
transient scheduler/GC jitter is filtered out. Between-run variance on the same
machine is ~5-15 % depending on transport; treat single-digit deltas across
runs as noise.

Regenerate the tables below from the latest run in `results.jsonl`:

```sh
ruby bench/report.rb --update-readme
```

## Throughput (PUSH/PULL, msg/s)

```
┌──────┐       ┌──────┐
│ PUSH │──────→│ PULL │
└──────┘       └──────┘
```

<!-- BEGIN push_pull -->
### 1 peer

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 128 B | 1.04M msg/s / 133 MB/s | 361.4k msg/s / 46.3 MB/s | 357.7k msg/s / 45.8 MB/s |
| 512 B | 1.11M msg/s / 568 MB/s | 251.9k msg/s / 129 MB/s | 249.7k msg/s / 128 MB/s |
| 2 KiB | 1.23M msg/s / 2.52 GB/s | 190.0k msg/s / 389 MB/s | 188.0k msg/s / 385 MB/s |
| 8 KiB | 1.23M msg/s / 10.09 GB/s | 98.6k msg/s / 808 MB/s | 93.3k msg/s / 764 MB/s |
| 32 KiB | 1.22M msg/s / 40.11 GB/s | 35.5k msg/s / 1.16 GB/s | 32.5k msg/s / 1.06 GB/s |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 128 B | 1.24M msg/s / 158 MB/s | 360.5k msg/s / 46.1 MB/s | 359.3k msg/s / 46.0 MB/s |
| 512 B | 1.17M msg/s / 598 MB/s | 214.9k msg/s / 110 MB/s | 225.6k msg/s / 115 MB/s |
| 2 KiB | 1.22M msg/s / 2.50 GB/s | 180.0k msg/s / 369 MB/s | 179.6k msg/s / 368 MB/s |
| 8 KiB | 1.21M msg/s / 9.94 GB/s | 96.8k msg/s / 793 MB/s | 93.0k msg/s / 762 MB/s |
| 32 KiB | 1.23M msg/s / 40.20 GB/s | 33.9k msg/s / 1.11 GB/s | 32.7k msg/s / 1.07 GB/s |

<!-- END push_pull -->

## Round-trip latency (REQ/REP, µs)

```
┌─────┐  req   ┌─────┐
│ REQ │───────→│ REP │
│     │←───────│     │
└─────┘  rep   └─────┘
```

Round-trip = one `req.send` + one `req.receive` + matching `rep` ops.
Latency is `1 / msgs_s` converted to µs.

<!-- BEGIN req_rep -->
| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 128 B | 9.09 µs | 48.8 µs | 63.5 µs |
| 512 B | 9.07 µs | 55.0 µs | 69.4 µs |
| 2 KiB | 8.71 µs | 59.7 µs | 72.2 µs |
| 8 KiB | 8.78 µs | 64.2 µs | 77.1 µs |
| 32 KiB | 8.74 µs | 79.6 µs | 95.0 µs |

<!-- END req_rep -->

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
# Full suite (one run_id shared across patterns for cross-pattern comparison)
RUN_ID=$(date +%Y-%m-%dT%H:%M:%S)
for d in push_pull req_rep router_dealer pub_sub; do
  OMQ_BENCH_RUN_ID=$RUN_ID bundle exec ruby --yjit bench/$d/omq.rb
done

# Regression report (latest vs previous run)
bundle exec ruby bench/report.rb

# Regenerate README tables from the latest run
bundle exec ruby bench/report.rb --update-readme

# Full comparison table
bundle exec ruby bench/report.rb --all
```
