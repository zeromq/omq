# Benchmarks

Measured in a Linux VM on a 2018 Intel Mac Mini, Ruby 4.0.2 +YJIT. Each cell
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
| 128 B | 1.65M msg/s / 212 MB/s* | 475.8k msg/s / 60.9 MB/s* | 506.3k msg/s / 64.8 MB/s* |
| 512 B | 1.69M msg/s / 866 MB/s* | 406.8k msg/s / 208 MB/s* | 420.9k msg/s / 216 MB/s* |
| 2 KiB | 1.69M msg/s / 3.46 GB/s* | 305.9k msg/s / 627 MB/s* | 313.6k msg/s / 642 MB/s* |
| 8 KiB | 1.85M msg/s / 15.19 GB/s* | 160.6k msg/s / 1.32 GB/s* | 162.1k msg/s / 1.33 GB/s* |
| 32 KiB | 1.85M msg/s / 60.55 GB/s* | 60.3k msg/s / 1.97 GB/s* | 56.8k msg/s / 1.86 GB/s* |
| 128 KiB | 1.86M msg/s / 243.32 GB/s* | 16.6k msg/s / 2.17 GB/s* | 14.9k msg/s / 1.96 GB/s* |
| 512 KiB | 1.85M msg/s / 970.71 GB/s* | 5.1k msg/s / 2.65 GB/s* | 5.3k msg/s / 2.80 GB/s* |

### 3 peers

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 128 B | 1.84M msg/s / 236 MB/s* | 508.2k msg/s / 65.1 MB/s* | 510.3k msg/s / 65.3 MB/s* |
| 512 B | 1.85M msg/s / 945 MB/s* | 417.2k msg/s / 214 MB/s* | 418.6k msg/s / 214 MB/s* |
| 2 KiB | 1.84M msg/s / 3.78 GB/s* | 307.9k msg/s / 631 MB/s* | 290.6k msg/s / 595 MB/s* |
| 8 KiB | 1.84M msg/s / 15.07 GB/s* | 163.4k msg/s / 1.34 GB/s* | 153.6k msg/s / 1.26 GB/s* |
| 32 KiB | 1.84M msg/s / 60.33 GB/s* | 54.7k msg/s / 1.79 GB/s* | 50.5k msg/s / 1.65 GB/s* |
| 128 KiB | 1.84M msg/s / 240.69 GB/s* | 15.2k msg/s / 2.00 GB/s* | 13.7k msg/s / 1.80 GB/s* |
| 512 KiB | 1.84M msg/s / 964.31 GB/s* | 4.6k msg/s / 2.42 GB/s* | 5.1k msg/s / 2.65 GB/s* |

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
| 128 B | 6.62 µs | 39.6 µs | 50.5 µs |
| 512 B | 6.94 µs | 41.0 µs | 52.6 µs |
| 2 KiB | 6.85 µs | 44.1 µs | 55.1 µs |
| 8 KiB | 6.88 µs | 49.1 µs | 59.7 µs |
| 32 KiB | 6.82 µs | 60.2 µs | 72.6 µs |
| 128 KiB | 6.79 µs | 113 µs | 134 µs |
| 512 KiB | 6.82 µs | 421 µs | 448 µs |

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
