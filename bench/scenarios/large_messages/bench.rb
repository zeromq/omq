# frozen_string_literal: true

# Large message throughput: 64B to 1MB.

$VERBOSE = nil

require_relative "../../../lib/omq"
require "async"
require "benchmark/ips"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "Large message throughput (tcp) | OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

SIZES = {
  "64 B"   => 64,
  "1 KB"   => 1024,
  "64 KB"  => 64 * 1024,
  "256 KB" => 256 * 1024,
  "1 MB"   => 1024 * 1024,
}

SIZES.each do |label, size|
  payload = "x" * size

  Async do
    pull = OMQ::PULL.new
    port = pull.bind("tcp://127.0.0.1:0").port
    push = OMQ::PUSH.connect("tcp://127.0.0.1:#{port}")

    20.times do
      push << payload
      pull.receive
    end

    Benchmark.ips do |x|
      x.config(warmup: 1, time: 3)
      x.report(label) do
        push << payload
        pull.receive
      end
    end
  ensure
    push&.close
    pull&.close
  end
end
