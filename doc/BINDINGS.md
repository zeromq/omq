# OMQ vs. other ZeroMQ bindings

Quick cross-language / cross-binding comparison. OMQ is a pure-Ruby ZMTP 3.1
implementation; the others wrap a native ZMQ library via FFI or JNI, or (in
JeroMQ's case) re-implement ZMTP in pure Java.

All numbers are from one machine, one run, same loopback. They are meant for
order-of-magnitude comparison, not decimal-point precision. Reproduce with
the scripts in `bench/scenarios/ffi_rzmq_vs_omq/` — numbers move by ±10%
between runs.

## Environment

- **CPU**: Intel Core i7-9750H @ 2.60 GHz, 4 physical cores
- **OS**: Linux 6.12 (Debian 13), x86_64
- **libzmq**: 4.3.5 (Debian `libzmq5`)
- **Ruby**: 4.0.2 with YJIT (pure-Ruby OMQ, ffi-rzmq, CZTop)
- **CPython**: 3.13.5 (pyzmq)
- **JRuby**: 10.0.5.0 on OpenJDK 21 (JeroMQ)
- **Transport**: TCP over `127.0.0.1`, one PUSH ↔ one PULL / one REQ ↔ one REP
- **HWM**: library defaults (1000)

## Bindings under test

| Binding | Language / Runtime | How it reaches the wire |
|---|---|---|
| **OMQ** 0.23.1 | MRI Ruby 4.0.2 + YJIT | pure Ruby, Async fibers, no native dep |
| **ffi-rzmq** 2.0.7 | MRI Ruby 4.0.2 + YJIT | FFI → libzmq 4.3.5 |
| **CZTop** 2.0.2 | MRI Ruby 4.0.2 + YJIT | FFI → CZMQ → libzmq 4.3.5 |
| **pyzmq** 26.4.0 | CPython 3.13.5 | Cython → libzmq 4.3.5 |
| **JeroMQ** 0.6.0 | JRuby 10 / OpenJDK 21 | pure Java re-implementation of ZMTP |

## PUSH/PULL throughput — 1,000,000 messages, one producer → one consumer

| Binding | 128 B msg/s | 128 B MB/s | 1024 B msg/s | 1024 B MB/s |
|---|---:|---:|---:|---:|
| JeroMQ (JRuby)        | **959,677** | 122.8 |   410,420 | 420.3 |
| OMQ (MRI, pure Ruby)  |   332,030   |  42.5 |   224,148 | 229.5 |
| pyzmq (CPython)       |   326,067   |  41.7 |   287,211 | 294.1 |
| CZTop (MRI)           |   268,342   |  34.3 |   225,171 | 230.6 |
| ffi-rzmq (MRI)        |    39,840   |   5.1 |    32,854 |  33.6 |

### Observations

- **JeroMQ runs away with throughput.** ~2.9× OMQ on small messages, ~1.8× on
  1 KB. The JVM JIT on a tight `send(byte[], 0)` loop against a pure-Java
  transport is hard to beat, and JeroMQ is mature (derived from the same
  codebase pedigree as libzmq itself).
- **OMQ edges pyzmq on small messages** (332k vs 326k) — a pure-Ruby fiber
  pipeline keeps up with Cython-wrapped libzmq when per-message overhead
  dominates. pyzmq pulls ahead at 1 KB because libzmq's C framing is still
  faster per byte than Ruby.
- **CZTop matches OMQ at 1 KB** (231 vs 230 MB/s) — at that size both
  are bandwidth-bound on loopback, and the FFI-per-call overhead
  disappears against the memcpy cost.
- **ffi-rzmq is ~10× slower than everything else.** Not libzmq's fault —
  the cost is in `ZMQ::Socket#recv_string`'s `String#replace` round-trip
  and the synchronous FFI::MemoryPointer allocation per call. For a Ruby
  user it's the worst option on throughput.

## REQ/REP round-trip latency — 100,000 round-trips, same thread/fiber

| Binding | 128 B rtt/s | 128 B µs/rtt | 1024 B rtt/s | 1024 B µs/rtt |
|---|---:|---:|---:|---:|
| OMQ (MRI, pure Ruby) | **14,167** | **70.6** | **12,902** | **77.5** |
| JeroMQ (JRuby)       | 14,948     |  66.9     | 13,118     | 76.2      |
| pyzmq (CPython)      | 14,232     |  70.3     | 13,925     | 71.8      |
| ffi-rzmq (MRI)       | 11,729     |  85.3     | 10,895     | 91.8      |
| CZTop (MRI)          |  5,547     | 180.3     |  5,617     | 178.0     |

### Observations

- **OMQ, JeroMQ, and pyzmq are in a dead heat** (~65–75 µs). Ping-pong
  latency on loopback is kernel-bound — whoever's client-side per-call
  overhead is under ~10 µs ends up within noise of everyone else.
- **ffi-rzmq pays its per-call FFI tax twice per round-trip** (send + recv),
  which shows up as ~20 µs extra.
- **CZTop is surprisingly slow at REQ/REP** — roughly 3× everyone else.
  Likely the CZMQ `zsock_recv` → `zmsg_t` path allocates more per call than
  the raw libzmq path does.

## Headline takeaways

1. **JeroMQ wins throughput**, by a wide margin on small messages.
2. **OMQ is the fastest Ruby option overall** — beats ffi-rzmq everywhere,
   beats CZTop on small-message throughput and on REQ/REP, ties CZTop at
   1 KB throughput. All despite being pure Ruby.
3. **On REQ/REP latency, runtime choice barely matters** — OMQ, JeroMQ and
   pyzmq all cluster around 65–75 µs. At that scale the bottleneck is TCP
   loopback, not the binding.
4. **ffi-rzmq is dramatically slower than every other binding on
   throughput**, and ~1.3× slower on REQ/REP. Not recommended for new
   Ruby projects if performance matters.
5. **CZTop matches OMQ on streaming throughput but loses badly on REQ/REP.**

## Caveats

- Each binding was benchmarked with the most idiomatic "just send and
  receive strings" API it offers. Tuning (zero-copy, pre-allocated buffers,
  batching) would shift results — especially for ffi-rzmq.
- JeroMQ numbers include JVM warmup inside the same process, with a 10k
  warmup loop before timing starts; JeroMQ is particularly sensitive to
  JIT settling.
- Single producer / single consumer, single pair. Scaling up connections,
  enabling CURVE, or adding a broker will change every number.
- The JeroMQ harness prints the PUSH/PULL and REQ/REP numbers cleanly but
  throws a teardown NPE from `Ctx.sendCommand` after the timing is already
  recorded — cosmetic, results are valid.
- The pyzmq harness runs each (pattern, size) combination in a fresh
  `subprocess` to work around a libzmq 4.3.5 teardown assertion
  (`Assertion failed: pfd.revents & POLLIN (src/signaler.cpp:238)`) that
  fires when successive REQ/REP tests share a process. No such workaround
  is needed for the Ruby or Java harnesses.

## Reproducing

```sh
# Ruby bindings
bundle exec ruby --yjit bench/scenarios/ffi_rzmq_vs_omq/omq.rb
ruby            --yjit bench/scenarios/ffi_rzmq_vs_omq/ffi_rzmq.rb
ruby            --yjit bench/scenarios/ffi_rzmq_vs_omq/cztop.rb

# CPython
python3 -u bench/scenarios/ffi_rzmq_vs_omq/pyzmq.py

# JRuby (requires JRuby 10+ on PATH as `jruby`)
jruby bench/scenarios/ffi_rzmq_vs_omq/jeromq.rb
```

Sources: `bench/scenarios/ffi_rzmq_vs_omq/` — five scripts, one per binding.
