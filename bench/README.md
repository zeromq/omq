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
| 64 B | 597.2k msg/s / 38.2 MB/s | 176.7k msg/s / 11.3 MB/s | 208.6k msg/s / 13.4 MB/s |
| 1 KiB | 582.2k msg/s / 596 MB/s | 163.3k msg/s / 167 MB/s | 161.0k msg/s / 165 MB/s |
| 8 KiB | 607.9k msg/s / 4.98 GB/s | 79.4k msg/s / 650 MB/s | 78.3k msg/s / 641 MB/s |
| 64 KiB | 608.4k msg/s / 39.87 GB/s | 19.7k msg/s / 1.29 GB/s | 16.3k msg/s / 1.07 GB/s |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 64 B | 459.7k msg/s / 29.4 MB/s | 164.6k msg/s / 10.5 MB/s | 188.4k msg/s / 12.1 MB/s |
| 1 KiB | 449.8k msg/s / 461 MB/s | 152.1k msg/s / 156 MB/s | 148.8k msg/s / 152 MB/s |
| 8 KiB | 448.4k msg/s / 3.67 GB/s | 79.6k msg/s / 652 MB/s | 74.2k msg/s / 608 MB/s |
| 64 KiB | 445.4k msg/s / 29.19 GB/s | 18.3k msg/s / 1.20 GB/s | 16.0k msg/s / 1.05 GB/s |

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
| 64 B | 16.4 µs | 64.4 µs | 84.8 µs |
| 1 KiB | 16.5 µs | 70.2 µs | 89.3 µs |
| 8 KiB | 16.3 µs | 79.2 µs | 96.7 µs |
| 64 KiB | 16.7 µs | 123 µs | 150 µs |

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
