# frozen_string_literal: true

# Reconnect storm: time for a PUSH client to reconnect after PULL server restart.

$VERBOSE = nil

require_relative "../../lib/omq"
require "async"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "Reconnect storm | OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

ITERATIONS = 10

Async do
  pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
  port = pull.last_tcp_port
  push = OMQ::PUSH.new(nil, linger: 0)
  push.reconnect_interval = 0.02
  push.connect("tcp://127.0.0.1:#{port}")
  sleep 0.3
  push << "warmup"; pull.receive

  times = []
  ITERATIONS.times do |i|
    pull.close
    sleep 0.3

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    pull = OMQ::PULL.bind("tcp://127.0.0.1:#{port}")
    push << "reconnect-#{i}"
    pull.receive
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    times << elapsed
  end

  avg = times.sum / times.size
  min = times.min
  max = times.max
  puts "  %d iterations: avg=%5.0f ms  min=%5.0f ms  max=%5.0f ms" % [ITERATIONS, avg * 1000, min * 1000, max * 1000]
ensure
  push&.close
  pull&.close
end
