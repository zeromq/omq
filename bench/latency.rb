# frozen_string_literal: true

$VERBOSE = nil

require_relative '../lib/omq'
require 'async'
require 'benchmark/ips'
require 'console'
Console.logger = Console::Logger.new(Console::Output::Null.new)

TRANSPORTS = {
  'inproc' => 'inproc://bench_latency',
  'ipc'    => 'ipc:///tmp/omq_bench_latency.sock',
  'tcp'    => 'tcp://127.0.0.1:9100',
}

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

payload = 'ping'

TRANSPORTS.each do |transport, addr|
  puts "--- #{transport} ---"

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
      req << payload
      req.receive
    end

    Benchmark.ips do |x|
      x.config(warmup: 1, time: 3)

      x.report('roundtrip') do
        req << payload
        req.receive
      end
    end

    responder.stop
  ensure
    req&.close
    rep&.close
  end

  puts
end
