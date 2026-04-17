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
| 128 B | 1.17M msg/s / 150 MB/s | 400.0k msg/s / 51.2 MB/s | 390.6k msg/s / 50.0 MB/s |
| 512 B | 1.23M msg/s / 629 MB/s | 296.9k msg/s / 152 MB/s | 288.5k msg/s / 148 MB/s |
| 2 KiB | 1.37M msg/s / 2.80 GB/s | 234.3k msg/s / 480 MB/s | 225.6k msg/s / 462 MB/s |
| 8 KiB | 1.38M msg/s / 11.27 GB/s | 105.2k msg/s / 862 MB/s | 106.4k msg/s / 871 MB/s |
| 32 KiB | 1.36M msg/s / 44.52 GB/s | 39.4k msg/s / 1.29 GB/s | 35.9k msg/s / 1.18 GB/s |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 128 B | 1.39M msg/s / 178 MB/s | 388.7k msg/s / 49.8 MB/s | 382.3k msg/s / 48.9 MB/s |
| 512 B | 1.34M msg/s / 684 MB/s | 283.2k msg/s / 145 MB/s | 277.7k msg/s / 142 MB/s |
| 2 KiB | 1.37M msg/s / 2.80 GB/s | 224.4k msg/s / 460 MB/s | 218.0k msg/s / 446 MB/s |
| 8 KiB | 1.36M msg/s / 11.15 GB/s | 104.2k msg/s / 854 MB/s | 104.1k msg/s / 853 MB/s |
| 32 KiB | 1.36M msg/s / 44.51 GB/s | 36.6k msg/s / 1.20 GB/s | 33.6k msg/s / 1.10 GB/s |

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
| 128 B | 8.42 µs | 44.4 µs | 57.7 µs |
| 512 B | 8.43 µs | 49.2 µs | 60.7 µs |
| 2 KiB | 8.06 µs | 51.9 µs | 64.1 µs |
| 8 KiB | 8.14 µs | 57.5 µs | 68.4 µs |
| 32 KiB | 8.04 µs | 71.3 µs | 87.4 µs |

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
