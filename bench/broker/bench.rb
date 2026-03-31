# frozen_string_literal: true

# Majordomo-style broker: messages/sec through a ROUTER-DEALER broker.
#
# Client → ROUTER (frontend) → DEALER (backend) → Worker
# Worker → DEALER (backend) → ROUTER (frontend) → Client

$VERBOSE = nil

require_relative "../../lib/omq"
require "async"
require "benchmark/ips"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "Broker throughput (inproc) | OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

N_WORKERS = 4
PAYLOAD   = ("x" * 64).freeze

Async do |task|
  OMQ::Transport::Inproc.reset!

  # Broker sockets
  frontend = OMQ::ROUTER.bind("inproc://broker_fe")
  backend  = OMQ::DEALER.bind("inproc://broker_be")

  # Broker pump: forward frontend → backend, backend → frontend
  broker_task = task.async do
    # Simple proxy: forward messages between frontend and backend
    # In a real broker you'd inspect identities. Here we just forward.
    loop do
      msg = frontend.receive
      # msg = [client_identity, "", request]
      backend << msg
    end
  end

  broker_back_task = task.async do
    loop do
      msg = backend.receive
      frontend << msg
    end
  end

  # Workers: REP connected to backend
  workers = N_WORKERS.times.map do
    task.async do
      rep = OMQ::REP.connect("inproc://broker_be")
      loop do
        msg = rep.receive
        rep << msg
      end
    ensure
      rep&.close
    end
  end

  # Client
  req = OMQ::REQ.new
  req.identity = "client-1"
  req.connect("inproc://broker_fe")

  # Warm up
  50.times { req << PAYLOAD; req.receive }

  Benchmark.ips do |x|
    x.config(warmup: 1, time: 3)
    x.report("broker roundtrip") do
      req << PAYLOAD
      req.receive
    end
  end

  broker_task.stop
  broker_back_task.stop
  workers.each(&:stop)
ensure
  req&.close
  frontend&.close
  backend&.close
end
