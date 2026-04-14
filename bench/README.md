# Benchmarks

Measured on Linux x86_64, Ruby 4.0.2 +YJIT. Each cell is the fastest of 3
timed rounds (~1 s each) after a calibration warmup, so transient
scheduler/GC jitter is filtered out. Between-run variance on the same
machine is ~5-15 % depending on transport; treat single-digit deltas
across runs as noise.

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
| 128 B | 818.0k msg/s / 105 MB/s | 327.8k msg/s / 42.0 MB/s | 328.7k msg/s / 42.1 MB/s |
| 512 B | 815.9k msg/s / 418 MB/s | 216.4k msg/s / 111 MB/s | 205.8k msg/s / 105 MB/s |
| 2 KiB | 917.1k msg/s / 1.88 GB/s | 180.4k msg/s / 370 MB/s | 159.6k msg/s / 327 MB/s |
| 8 KiB | 931.7k msg/s / 7.63 GB/s | 93.5k msg/s / 766 MB/s | 94.8k msg/s / 777 MB/s |
| 32 KiB | 919.2k msg/s / 30.12 GB/s | 34.6k msg/s / 1.13 GB/s | 32.4k msg/s / 1.06 GB/s |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 128 B | 461.4k msg/s / 59.1 MB/s | 238.3k msg/s / 30.5 MB/s | 239.0k msg/s / 30.6 MB/s |
| 512 B | 450.6k msg/s / 231 MB/s | 149.1k msg/s / 76.3 MB/s | 150.1k msg/s / 76.9 MB/s |
| 2 KiB | 461.3k msg/s / 945 MB/s | 145.1k msg/s / 297 MB/s | 131.3k msg/s / 269 MB/s |
| 8 KiB | 461.5k msg/s / 3.78 GB/s | 80.5k msg/s / 660 MB/s | 82.0k msg/s / 672 MB/s |
| 32 KiB | 463.8k msg/s / 15.20 GB/s | 30.9k msg/s / 1.01 GB/s | 28.5k msg/s / 935 MB/s |

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
| 128 B | 11.5 µs | 54.2 µs | 68.6 µs |
| 512 B | 11.6 µs | 59.2 µs | 70.5 µs |
| 2 KiB | 11.2 µs | 62.1 µs | 75.7 µs |
| 8 KiB | 11.3 µs | 68.1 µs | 78.3 µs |
| 32 KiB | 11.6 µs | 89.9 µs | 111 µs |

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
