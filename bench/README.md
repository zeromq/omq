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
| 64 B | 625.1k msg/s / 40.0 MB/s | 187.1k msg/s / 12.0 MB/s | 235.3k msg/s / 15.1 MB/s |
| 1 KiB | 612.5k msg/s / 627 MB/s | 180.1k msg/s / 184 MB/s | 179.9k msg/s / 184 MB/s |
| 8 KiB | 658.4k msg/s / 5.39 GB/s | 91.5k msg/s / 750 MB/s | 94.9k msg/s / 777 MB/s |
| 64 KiB | 652.9k msg/s / 42.79 GB/s | 20.3k msg/s / 1.33 GB/s | 17.8k msg/s / 1.17 GB/s |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 64 B | 487.4k msg/s / 31.2 MB/s | 123.1k msg/s / 7.88 MB/s | 200.9k msg/s / 12.8 MB/s |
| 1 KiB | 491.6k msg/s / 503 MB/s | 140.1k msg/s / 144 MB/s | 164.2k msg/s / 168 MB/s |
| 8 KiB | 490.0k msg/s / 4.01 GB/s | 84.0k msg/s / 688 MB/s | 85.5k msg/s / 700 MB/s |
| 64 KiB | 478.1k msg/s / 31.33 GB/s | 18.7k msg/s / 1.22 GB/s | 17.7k msg/s / 1.16 GB/s |

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
| 64 B | 15.0 µs | 58.7 µs | 72.4 µs |
| 1 KiB | 14.9 µs | 63.3 µs | 77.0 µs |
| 8 KiB | 15.3 µs | 70.2 µs | 82.2 µs |
| 64 KiB | 14.9 µs | 108 µs | 133 µs |

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
