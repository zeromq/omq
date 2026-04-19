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
| 128 B | 1.08M msg/s / 138 MB/s | 423.1k msg/s / 54.2 MB/s | 416.9k msg/s / 53.4 MB/s |
| 512 B | 1.12M msg/s / 572 MB/s | 331.3k msg/s / 170 MB/s | 292.0k msg/s / 149 MB/s |
| 2 KiB | 1.21M msg/s / 2.48 GB/s | 229.7k msg/s / 470 MB/s | 224.5k msg/s / 460 MB/s |
| 8 KiB | 1.36M msg/s / 11.13 GB/s | 110.8k msg/s / 908 MB/s | 106.7k msg/s / 874 MB/s |
| 32 KiB | 1.35M msg/s / 44.35 GB/s | 38.4k msg/s / 1.26 GB/s | 36.5k msg/s / 1.20 GB/s |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 128 B | 1.41M msg/s / 180 MB/s | 424.9k msg/s / 54.4 MB/s | 414.4k msg/s / 53.0 MB/s |
| 512 B | 1.28M msg/s / 655 MB/s | 302.8k msg/s / 155 MB/s | 270.0k msg/s / 138 MB/s |
| 2 KiB | 1.35M msg/s / 2.76 GB/s | 217.0k msg/s / 444 MB/s | 208.8k msg/s / 428 MB/s |
| 8 KiB | 1.29M msg/s / 10.55 GB/s | 106.1k msg/s / 869 MB/s | 104.2k msg/s / 853 MB/s |
| 32 KiB | 1.38M msg/s / 45.15 GB/s | 36.0k msg/s / 1.18 GB/s | 32.2k msg/s / 1.06 GB/s |

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
| 128 B | 8.81 µs | 43.5 µs | 59.8 µs |
| 512 B | 9.03 µs | 51.6 µs | 61.4 µs |
| 2 KiB | 9.06 µs | 50.9 µs | 63.9 µs |
| 8 KiB | 8.38 µs | 57.7 µs | 67.4 µs |
| 32 KiB | 8.62 µs | 69.3 µs | 91.7 µs |

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
