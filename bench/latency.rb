# frozen_string_literal: true

$VERBOSE = nil

require_relative '../lib/omq'
require 'async'
require 'benchmark/ips'
require 'console'
Console.logger = Console::Logger.new(Console::Output::Null.new)

TRANSPORTS = {
  'inproc' => ->(tag) { "inproc://bench_lat_#{tag}" },
  'ipc'    => ->(tag) { "ipc:///tmp/omq_bench_lat_#{tag}.sock" },
  'tcp'    => ->(tag) { "tcp://127.0.0.1:#{9100 + tag.hash.abs % 1000}" },
}

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

payload = 'ping'

TRANSPORTS.each do |transport, addr_fn|
  puts "--- #{transport} (1 peer) ---"

  addr = addr_fn.call("#{transport}_single")

  Async do |task|
    rep = OMQ::REP.bind(addr)
    req = OMQ::REQ.connect(addr)

    responder = task.async do
      loop do
        msg = rep.receive
        rep << msg
      end
    end

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

  # Multi-peer latency: DEALER fans out to N REPs via ROUTER
  puts "--- #{transport} (3 peers) ---"

  router_addr = addr_fn.call("#{transport}_multi")

  Async do |task|
    if transport == 'inproc'
      OMQ::Transport::Inproc.reset!
    end

    router = OMQ::ROUTER.bind(router_addr)
    dealers = 3.times.map do |i|
      d = OMQ::DEALER.new
      d.identity = "d#{i}"
      d.connect(router_addr)
      d
    end

    # Responder: echo back to sender
    responder = task.async do
      loop do
        msg = router.receive
        identity = msg[0]
        router.send_to(identity, msg[1..])
      end
    end

    # Warm up via first dealer
    100.times do
      dealers[0] << payload
      dealers[0].receive
    end

    Benchmark.ips do |x|
      x.config(warmup: 1, time: 3)

      x.report('roundtrip') do
        dealers[0] << payload
        dealers[0].receive
      end
    end

    responder.stop
  ensure
    dealers&.each(&:close)
    router&.close
  end

  puts
end
