# frozen_string_literal: true

# Multi-frame message throughput: 1-part vs 5-part vs 10-part.

$VERBOSE = nil

require_relative "../../lib/omq"
require "async"
require "benchmark/ips"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "Multi-frame throughput (inproc) | OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

FRAME_COUNTS = [1, 5, 10]

FRAME_COUNTS.each do |n_frames|
  payload = n_frames.times.map { "x" * 64 }

  Async do
    OMQ::Transport::Inproc.reset!

    pull = OMQ::PULL.bind("inproc://bench_mf_#{n_frames}")
    push = OMQ::PUSH.connect("inproc://bench_mf_#{n_frames}")

    100.times { push << payload; pull.receive }

    Benchmark.ips do |x|
      x.config(warmup: 1, time: 3)
      x.report("#{n_frames} frame(s)") do
        push << payload
        pull.receive
      end
    end
  ensure
    push&.close
    pull&.close
  end
end
