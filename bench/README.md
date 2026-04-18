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
| 128 B | 1.64M msg/s / 210 MB/s | 293.5k msg/s / 37.6 MB/s | 307.8k msg/s / 39.4 MB/s |
| 512 B | 1.63M msg/s / 833 MB/s | 253.2k msg/s / 130 MB/s | 231.7k msg/s / 119 MB/s |
| 2 KiB | 2.01M msg/s / 4.12 GB/s | 211.1k msg/s / 432 MB/s | 180.1k msg/s / 369 MB/s |
| 8 KiB | 2.00M msg/s / 16.41 GB/s | 101.0k msg/s / 827 MB/s | 94.5k msg/s / 774 MB/s |
| 32 KiB | 1.99M msg/s / 65.14 GB/s | 34.4k msg/s / 1.13 GB/s | 32.4k msg/s / 1.06 GB/s |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 128 B | 2.01M msg/s / 257 MB/s | 295.6k msg/s / 37.8 MB/s | 309.8k msg/s / 39.7 MB/s |
| 512 B | 1.98M msg/s / 1.01 GB/s | 221.1k msg/s / 113 MB/s | 227.4k msg/s / 116 MB/s |
| 2 KiB | 2.04M msg/s / 4.19 GB/s | 164.7k msg/s / 337 MB/s | 171.5k msg/s / 351 MB/s |
| 8 KiB | 2.01M msg/s / 16.48 GB/s | 93.7k msg/s / 767 MB/s | 92.8k msg/s / 760 MB/s |
| 32 KiB | 1.98M msg/s / 64.98 GB/s | 32.6k msg/s / 1.07 GB/s | 29.4k msg/s / 964 MB/s |

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
| 128 B | 8.71 µs | 50.6 µs | 64.4 µs |
| 512 B | 8.42 µs | 57.4 µs | 67.6 µs |
| 2 KiB | 8.32 µs | 59.7 µs | 73.4 µs |
| 8 KiB | 8.26 µs | 68.4 µs | 79.8 µs |
| 32 KiB | 8.27 µs | 93.5 µs | 113 µs |

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
