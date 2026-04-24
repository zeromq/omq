# Benchmarks

Measured in a Linux VM on a 2019 Intel MacBook Pro, Ruby 4.0.2 +YJIT. Each cell
is the fastest of 3 timed rounds (~1 s each) after a calibration warmup, so
transient scheduler/GC jitter is filtered out. Between-run variance on the same
machine is ~5-15 % depending on transport; treat single-digit deltas across
runs as noise.

### Reading the numbers (\*)

The same `String` payload is reused across every send — no per-message
allocation. The primary metric is **msg/s** (raw send-path throughput,
what the library can actually push through its queues and codec). The
**MB/s\*** figures are nominal — they're `msg/s × msg_size`, which for
inproc overstates real memory bandwidth (inproc passes the `String` by
reference through the engine queue — no bytes are copied). For IPC/TCP
the bytes really do traverse the kernel, so MB/s there is meaningful
within kernel-buffer/loopback limits. Cross-impl comparison is fairer
this way: Ruby's `String#dup` is copy-on-write while Crystal's
`Bytes#dup` is a real memcpy, so a `.dup`-per-send bench would compare
allocator speed rather than send speed.

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
| 128 B | 1.39M msg/s / 178 MB/s* | 359.6k msg/s / 46.0 MB/s* | 418.0k msg/s / 53.5 MB/s* |
| 512 B | 1.46M msg/s / 747 MB/s* | 234.9k msg/s / 120 MB/s* | 340.2k msg/s / 174 MB/s* |
| 2 KiB | 1.44M msg/s / 2.94 GB/s* | 200.2k msg/s / 410 MB/s* | 209.6k msg/s / 429 MB/s* |
| 8 KiB | 1.64M msg/s / 13.42 GB/s* | 102.8k msg/s / 842 MB/s* | 101.2k msg/s / 829 MB/s* |
| 32 KiB | 1.61M msg/s / 52.88 GB/s* | 38.1k msg/s / 1.25 GB/s* | 36.1k msg/s / 1.18 GB/s* |
| 128 KiB | 1.70M msg/s / 222.22 GB/s* | 10.2k msg/s / 1.33 GB/s* | 9.8k msg/s / 1.29 GB/s* |
| 512 KiB | 1.68M msg/s / 878.60 GB/s* | 3.0k msg/s / 1.59 GB/s* | 3.4k msg/s / 1.79 GB/s* |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 128 B | 1.65M msg/s / 211 MB/s* | 254.4k msg/s / 32.6 MB/s* | 428.3k msg/s / 54.8 MB/s* |
| 512 B | 1.59M msg/s / 812 MB/s* | 228.1k msg/s / 117 MB/s* | 285.7k msg/s / 146 MB/s* |
| 2 KiB | 1.46M msg/s / 3.00 GB/s* | 166.5k msg/s / 341 MB/s* | 210.9k msg/s / 432 MB/s* |
| 8 KiB | 1.63M msg/s / 13.33 GB/s* | 94.8k msg/s / 777 MB/s* | 102.1k msg/s / 837 MB/s* |
| 32 KiB | 1.49M msg/s / 48.74 GB/s* | 29.4k msg/s / 964 MB/s* | 33.0k msg/s / 1.08 GB/s* |
| 128 KiB | 1.57M msg/s / 206.14 GB/s* | 9.8k msg/s / 1.28 GB/s* | 9.3k msg/s / 1.22 GB/s* |
| 512 KiB | 1.67M msg/s / 875.98 GB/s* | 2.2k msg/s / 1.17 GB/s* | 3.1k msg/s / 1.65 GB/s* |

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
| 128 B | 8.49 µs | 45.6 µs | 61.8 µs |
| 512 B | 8.92 µs | 53.0 µs | 62.6 µs |
| 2 KiB | 8.60 µs | 51.3 µs | 65.7 µs |
| 8 KiB | 8.55 µs | 66.8 µs | 69.3 µs |
| 32 KiB | 8.14 µs | 88.8 µs | 86.8 µs |
| 128 KiB | 8.38 µs | 179 µs | 203 µs |
| 512 KiB | 9.12 µs | 664 µs | 701 µs |

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
