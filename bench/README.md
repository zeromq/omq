# Benchmarks

Measured with `benchmark-ips` on Linux x86_64, Ruby 4.0.1 +YJIT.

## Throughput (push/pull, msg/s)

| Message size | inproc | ipc | tcp |
|---|---|---|---|
| 64 B | 184k | 35k | 18k |
| 256 B | 167k | 36k | 27k |
| 1024 B | 172k | 29k | 26k |
| 4096 B | 164k | 13k | 15k |

## Latency (req/rep roundtrip)

| | inproc | ipc | tcp |
|---|---|---|---|
| roundtrip | 13 µs | 70 µs | 97 µs |

## Running

```sh
ruby --yjit bench/throughput.rb
ruby --yjit bench/latency.rb
```
