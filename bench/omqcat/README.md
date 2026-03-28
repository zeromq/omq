# omqcat Benchmarks

Measured on Linux x86_64, Ruby 4.0.2 +YJIT (io_uring).

## Throughput (PUSH/PULL, piping `seq N`)

```
                  stdin
                    │
┌───────────────────▼────────────────────┐
│  seq 10000 | omqcat push -c ipc://     │
└───────────────────┬────────────────────┘
                    │ IPC/TCP
┌───────────────────▼────────────────────┐
│  omqcat pull -b ipc:// > /dev/null     │
└────────────────────────────────────────┘
```

| Transport | msg/s |
|-----------|-------|
| tcp | 126k |
| ipc | 56k |

## Latency (REQ/REP, `-D "ping" -i 0`)

```
┌─────────────────────────────────────────┐
│  omqcat req -c ipc:// -D ping -i 0      │
└──────────────────┬──────────────────────┘
                   │  req/rep
┌──────────────────▼──────────────────────┐
│  omqcat rep -b ipc:// --echo            │
└─────────────────────────────────────────┘
```

| Transport | µs/roundtrip |
|-----------|-------------|
| tcp | 170 |
| ipc | 179 |

The overhead vs the direct Ruby API (~2x throughput, ~3x latency) comes
from stdin/stdout line processing per message. This is expected for a CLI tool.

## Running

```sh
sh bench/omqcat/throughput.sh [count]   # default: 10000
sh bench/omqcat/latency.sh [count]      # default: 1000
```
