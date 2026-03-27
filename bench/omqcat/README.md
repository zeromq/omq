# omqcat Benchmarks

Measured on Linux x86_64, Ruby 4.0.2 +YJIT (io_uring).

## Throughput (PUSH/PULL, piping `seq N`)

| Transport | msg/s |
|-----------|-------|
| tcp | 9.3k |
| ipc | 9.8k |

## Latency (REQ/REP, `-D "ping" -i 0`)

| Transport | µs/roundtrip |
|-----------|-------------|
| tcp | 1,225 |
| ipc | 1,162 |

The overhead vs the direct Ruby API (~3–4x throughput, ~14–19x latency) comes
from stdin/stdout line processing per message. This is expected for a CLI tool.

## Running

```sh
sh bench/omqcat/throughput.sh [count]   # default: 10000
sh bench/omqcat/latency.sh [count]      # default: 1000
```
