# Flush Batching Benchmark

Measures throughput under burst load where the send queue accumulates
multiple messages before the pump drains them — exercising the batch
write + single flush path.

**Setup**: 1000-message bursts, 256 B payload, 20 rounds, median reported.

```
ruby bench/flush_batching/bench.rb
```

## Results

Linux x86_64, Ruby 4.0.2 (no JIT).

### PUSH/PULL

| Transport | Before    | After      | Speedup |
|-----------|-----------|------------|---------|
| ipc       | 29,605/s  | 87,487/s   | **3.0x** |
| tcp       | 24,365/s  | 83,170/s   | **3.4x** |

### PUB/SUB

| Transport | Subs | Before   | After     | Speedup  |
|-----------|------|----------|-----------|----------|
| ipc       | 1    | 28,825/s | 80,357/s  | **2.8x** |
| ipc       | 5    | 5,901/s  | 18,566/s  | **3.1x** |
| ipc       | 10   | 2,790/s  | 9,525/s   | **3.4x** |
| tcp       | 1    | 22,373/s | 67,228/s  | **3.0x** |
| tcp       | 5    | 4,588/s  | 18,280/s  | **4.0x** |
| tcp       | 10   | 2,314/s  | 9,205/s   | **4.0x** |

## Why

Before batching, every `Connection#send_message` called `io.flush`
immediately — one syscall per message per connection. For PUB with
N subscribers, one published message triggered N flushes.

After batching, the send pump drains all queued messages first
(`write_message` buffers without flushing), then flushes each
connection once. Under burst load the flush count drops from
`N_msgs × N_conns` to `N_conns` per batch cycle.

Under light load (queue never deeper than 1), the batch size is 1
and performance is identical to the old path.
