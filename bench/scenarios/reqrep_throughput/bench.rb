# frozen_string_literal: true

# REQ/REP sustained throughput (not just roundtrip latency).
# Measures how many request-reply cycles/sec with pipelined requests.

$VERBOSE = nil

require_relative "../../../lib/omq"
require "async"
require "benchmark/ips"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "REQ/REP throughput | OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

TRANSPORTS = {
  "inproc" => ->(tag) { "inproc://bench_rr_#{tag}" },
  "ipc"    => ->(tag) { "ipc:///tmp/omq_bench_rr_#{tag}.sock" },
  "tcp"    => ->(tag) { "tcp://127.0.0.1:#{9100 + tag.hash.abs % 1000}" },
}

TRANSPORTS.each do |transport, addr_fn|
  addr = addr_fn.call(transport)

  Async do |task|
    rep = OMQ::REP.bind(addr)
    req = OMQ::REQ.connect(addr)

    responder = task.async do
      loop do
        msg = rep.receive
        rep << msg
      end
    end

    # Warm up
    100.times do
      req << "ping"
      req.receive
    end

    Benchmark.ips do |x|
      x.config(warmup: 1, time: 3)
      x.report("#{transport} 64B") do
        req << ("x" * 64)
        req.receive
      end
    end

    responder.stop
  ensure
    req&.close
    rep&.close
  end
end
