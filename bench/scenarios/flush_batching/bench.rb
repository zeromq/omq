# frozen_string_literal: true

# Flush-batching benchmark: measures throughput under burst load
# where the send queue accumulates multiple messages before the
# pump drains them — exercising the batch write + single flush path.

$VERBOSE = nil

require_relative "../../lib/omq"
require "async"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "Flush batching | OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

BURST   = 1000
ROUNDS  = 20
PAYLOAD = ("x" * 256).freeze

def bench_push_pull(transport, addr)
  times = []

  Async do
    pull = OMQ::PULL.bind(addr)
    push = OMQ::PUSH.connect(addr)
    sleep 0.05

    # Warm up
    50.times { push << PAYLOAD; pull.receive }

    ROUNDS.times do
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Burst-enqueue all messages, then drain
      BURST.times { push << PAYLOAD }
      BURST.times { pull.receive }

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      times << elapsed
    end
  ensure
    push&.close
    pull&.close
  end

  times.sort!
  median = times[times.size / 2]
  rate   = (BURST / median).round
  puts "  PUSH/PULL %-6s  %6d msg/s  (median %.1f ms for %d msgs)" % [transport, rate, median * 1000, BURST]
end

def bench_pub_sub(transport, addr, n_subs:)
  times = []

  Async do
    pub  = OMQ::PUB.bind(addr)
    subs = n_subs.times.map { OMQ::SUB.connect(addr, subscribe: "") }
    sleep 0.05

    # Warm up
    50.times { pub << PAYLOAD; subs.each(&:receive) }

    ROUNDS.times do
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      BURST.times { pub << PAYLOAD }
      BURST.times { subs.each(&:receive) }

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      times << elapsed
    end
  ensure
    subs&.each(&:close)
    pub&.close
  end

  times.sort!
  median = times[times.size / 2]
  rate   = (BURST / median).round
  puts "  PUB/SUB   %-6s  %6d msg/s  (%d subs, median %.1f ms for %d msgs)" % [transport, rate, n_subs, median * 1000, BURST]
end

puts "--- PUSH/PULL (burst of #{BURST}) ---"
bench_push_pull("ipc", "ipc:///tmp/omq_bench_batch_pp.sock")
bench_push_pull("tcp", "tcp://127.0.0.1:19876")
puts

puts "--- PUB/SUB (burst of #{BURST}) ---"
[1, 5, 10].each do |n|
  bench_pub_sub("ipc", "ipc:///tmp/omq_bench_batch_ps_#{n}.sock", n_subs: n)
end
[1, 5, 10].each do |n|
  bench_pub_sub("tcp", "tcp://127.0.0.1:#{19900 + n}", n_subs: n)
end
