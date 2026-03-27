# fork + OMQ vs Ractor::Port

You don't need Ractors for parallelism. With ZMQ, just fork.

Each forked worker is a separate OS process — true parallelism, no GVL.
Workers communicate via IPC sockets, same as they would across machines
via TCP. Scaling from processes on one box to services across a cluster
is a config change, not a rewrite.

## Topology

```
producer → 4 workers×fib(28) → collector
```

Each worker receives a Marshal'd number, computes `fib(28)` (~2 ms CPU),
and sends back the Marshal'd result — a realistic compute pipeline.

- **fork + OMQ**: workers are forked processes, communicate via PUSH/PULL over IPC
- **Ractor::Port**: workers are Ractors, communicate via `Ractor.receive` / `Port#send`

## Results

Ruby 4.0.2 +YJIT, Linux x86_64 (1000 tasks):

```
fork + OMQ     (4 processes):  267 tasks/s  (3.8s)
Ractor::Port   (4 ractors):   199 tasks/s  (5.0s)
```

Fork + OMQ is faster, simpler, and works on every Ruby since 1.8.
Ractors are still experimental and come with isolation constraints
(shareable objects, no closures, no instance variables across boundaries).

## Running

```sh
ruby --yjit bench/ractors_vs_fork/bench.rb fork
ruby --yjit bench/ractors_vs_fork/bench.rb ractors
```
