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
| 64 B | 580.2k msg/s | 168.7k msg/s | 194.6k msg/s |
| 1 KiB | 563.6k msg/s | 160.9k msg/s | 147.9k msg/s |
| 8 KiB | 604.5k msg/s | 79.8k msg/s | 74.6k msg/s |
| 64 KiB | 584.5k msg/s | 19.2k msg/s | 16.5k msg/s |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 64 B | 447.6k msg/s | 125.5k msg/s | 179.0k msg/s |
| 1 KiB | 434.9k msg/s | 139.3k msg/s | 134.8k msg/s |
| 8 KiB | 436.1k msg/s | 75.2k msg/s | 69.7k msg/s |
| 64 KiB | 434.1k msg/s | 19.0k msg/s | 16.1k msg/s |

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
| 64 B | 16.4 µs | 63.6 µs | 85.6 µs |
| 1 KiB | 16.9 µs | 73.1 µs | 91.4 µs |
| 8 KiB | 16.9 µs | 80.2 µs | 100 µs |
| 64 KiB | 16.7 µs | 147 µs | 174 µs |

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
