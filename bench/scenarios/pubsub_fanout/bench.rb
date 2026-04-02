# frozen_string_literal: true

# PUB/SUB fan-out: throughput with N subscribers.

$VERBOSE = nil

require_relative "../../lib/omq"
require "async"
require "benchmark/ips"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "PUB/SUB fan-out | OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

SUBSCRIBER_COUNTS = [1, 5, 10]

SUBSCRIBER_COUNTS.each do |n_subs|
  Async do
    OMQ::Transport::Inproc.reset!

    pub = OMQ::PUB.bind("inproc://bench_fanout_#{n_subs}")
    subs = n_subs.times.map { OMQ::SUB.connect("inproc://bench_fanout_#{n_subs}", subscribe: "") }

    sleep 0.01

    # Warm up
    50.times do
      pub << "warmup"
      subs.each(&:receive)
    end

    Benchmark.ips do |x|
      x.config(warmup: 1, time: 3)
      x.report("#{n_subs} subs") do
        pub << ("x" * 64)
        subs.each(&:receive)
      end
    end
  ensure
    subs&.each(&:close)
    pub&.close
  end
end
