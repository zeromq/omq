# Pipeline Benchmark (fib)

Fan-out/fan-in pipeline where each worker computes `fib(n)`.

Measured on Linux x86_64, Ruby 4.0.2 +YJIT (io_uring), 4 CPUs.

## Topology

```
+----------+     +--------+     +------+
| producer |-IPC-| worker |-IPC-| sink |
| PUSH     |     | pipe×4 |     | PULL |
+----------+     +--------+     +------+
```

Producer sends N integers cycling 1..20.
Each worker computes `fib(n)` and forwards the result.
Sink collects all results.

## Multi-process (`pipeline.sh`)

4 separate `omq pipe` processes, one per worker.

## Ractors (`pipeline_ractors.sh`)

Single `omq pipe -P 4` process with 4 Ractor workers.

## Results

### Light work: 1M messages, fib(1..20)

| Mode | msg/s | Time |
|------|------:|-----:|
| Multi-process (4 pipes) | 50,471 | 19.8s |
| Ractors (-P 4)          |  9,635 | 103.8s |

### Heavy work: 10k messages, fib(1..29)

| Mode | msg/s | Time |
|------|------:|-----:|
| Multi-process (4 pipes) | 1,418 | 7.1s |
| Ractors (-P 4)          | 1,739 | 5.7s |

Ractors overtake multi-process when per-message CPU work dominates IPC overhead.

## Running

```sh
sh bench/cli/fib_pipeline/pipeline.sh [count] [fib_max]
sh bench/cli/fib_pipeline/pipeline_ractors.sh [count] [fib_max] [workers]
```
