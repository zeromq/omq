# frozen_string_literal: true

# HWM backpressure: throughput with a slow consumer.
#
# Measures how PUSH/PULL behaves when the consumer is slower than the
# producer and the send HWM is hit.

$VERBOSE = nil

require_relative "../../lib/omq"
require "async"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "HWM backpressure | OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

N_MESSAGES = 10_000
PAYLOAD    = ("x" * 64).freeze

[10, 100, 1000, 0].each do |hwm|
  label = hwm == 0 ? "unbounded" : "HWM=#{hwm}"

  Async do |task|
    OMQ::Transport::Inproc.reset!

    pull = OMQ::PULL.bind("inproc://bench_hwm_#{hwm}", recv_hwm: hwm)
    push = OMQ::PUSH.connect("inproc://bench_hwm_#{hwm}", send_hwm: hwm)

    # Slow consumer: sleeps 10 µs between receives
    received = 0
    consumer = task.async do
      N_MESSAGES.times do
        pull.receive
        received += 1
        sleep 0.00001 # 10 µs
      end
    end

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    N_MESSAGES.times { push << PAYLOAD }
    consumer.wait
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

    rate = N_MESSAGES / elapsed
    puts "  %-12s %7.0f msg/s  (%5.0f ms)" % [label, rate, elapsed * 1000]
  ensure
    push&.close
    pull&.close
  end
end
