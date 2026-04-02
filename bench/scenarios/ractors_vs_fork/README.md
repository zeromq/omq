# fork + OMQ vs Ractor::Port

You don't need Ractors for parallelism. With ZMQ, just fork.

Each forked worker is a separate OS process — true parallelism, no GVL.
Workers communicate via IPC sockets, same as they would across machines
via TCP. Scaling from processes on one box to services across a cluster
is a config change, not a rewrite.

## Topology

Each worker receives a Marshal'd number, computes `fib(28)` (~2 ms CPU),
and sends back the Marshal'd result — a realistic compute pipeline.

**fork + OMQ** — workers are forked processes, PUSH/PULL over IPC:

```
                   ┌───────────┐
             ┌────→│ worker pid│────┐
             │     └───────────┘    │
┌────────┐   │     ┌───────────┐    │   ┌───────────┐
│producer│─PUSH─┬─→│ worker pid│─┬─PULL─│ collector │
└────────┘   │  │  └───────────┘ │  │   └───────────┘
             │  │  ┌───────────┐ │  │
             │  └─→│ worker pid│─┘  │
             │     └───────────┘    │
             │     ┌───────────┐    │
             └────→│ worker pid│────┘
                   └───────────┘
```

**Ractor::Port** — workers are Ractors, in-process message passing:

```
             ┌────────┐
       ┌────→│ Ractor │────┐
       │     └────────┘    │
       │     ┌────────┐    │
main──send┬─→│ Ractor │─┬─port──main
       │  │  └────────┘ │  │
       │  │  ┌────────┐ │  │
       │  └─→│ Ractor │─┘  │
       │     └────────┘    │
       │     ┌────────┐    │
       └────→│ Ractor │────┘
             └────────┘
```

## Results

Ruby 4.0.2 +YJIT, Linux x86_64 (1000 tasks):

```
fork + OMQ     (4 processes):  416 tasks/s  (2.4s)
Ractor::Port   (4 ractors):   332 tasks/s  (3.0s)
```

Fork + OMQ is faster and simpler.
Ractors are still experimental and come with isolation constraints
(shareable objects, no closures, no instance variables across boundaries).

## Running

```sh
ruby --yjit bench/ractors_vs_fork/bench.rb fork
ruby --yjit bench/ractors_vs_fork/bench.rb ractors
```
