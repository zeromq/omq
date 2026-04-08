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
| 64 B | 530.9k msg/s | 113.1k msg/s | 176.4k msg/s |
| 1 KiB | 554.0k msg/s | 105.6k msg/s | 133.8k msg/s |
| 8 KiB | 515.2k msg/s | 64.6k msg/s | 67.6k msg/s |
| 64 KiB | 559.8k msg/s | 14.3k msg/s | 13.0k msg/s |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 64 B | 417.8k msg/s | 141.5k msg/s | 150.2k msg/s |
| 1 KiB | 415.0k msg/s | 124.2k msg/s | 107.8k msg/s |
| 8 KiB | 404.4k msg/s | 58.6k msg/s | 54.1k msg/s |
| 64 KiB | 383.3k msg/s | 14.7k msg/s | 12.8k msg/s |

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
| 64 B | 17.3 µs | 73.4 µs | 97.8 µs |
| 1 KiB | 19.7 µs | 85.5 µs | 111 µs |
| 8 KiB | 18.6 µs | 93.8 µs | 129 µs |
| 64 KiB | 18.3 µs | 153 µs | 198 µs |

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
