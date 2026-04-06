# frozen_string_literal: true

# Draft socket types vs their classic equivalents.
#
# SCATTER/GATHER vs PUSH/PULL — should be identical (confirms no SingleFrame overhead)
# CLIENT/SERVER vs REQ/REP — CLIENT/SERVER has no envelope overhead
# RADIO/DISH vs PUB/SUB — exact group match vs prefix match

$VERBOSE = nil

require_relative "../../../lib/omq"
require "async"
require "benchmark/ips"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "Draft vs classic socket types (inproc) | OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

PAYLOAD = ("x" * 64).freeze

# --- PUSH/PULL vs SCATTER/GATHER ---

puts "--- Pipeline: PUSH/PULL vs SCATTER/GATHER ---"

Async do
  OMQ::Transport::Inproc.reset!

  pull = OMQ::PULL.bind("inproc://bench_push")
  push = OMQ::PUSH.connect("inproc://bench_push")
  100.times do
    push << PAYLOAD
    pull.receive
  end

  gather  = OMQ::GATHER.bind("inproc://bench_scatter")
  scatter = OMQ::SCATTER.connect("inproc://bench_scatter")
  100.times do
    scatter << PAYLOAD
    gather.receive
  end

  Benchmark.ips do |x|
    x.config(warmup: 1, time: 3)
    x.report("PUSH/PULL") do
      push << PAYLOAD
      pull.receive
    end
    x.report("SCATTER/GATHER") do
      scatter << PAYLOAD
      gather.receive
    end
    x.compare!
  end
ensure
  push&.close
  pull&.close
  scatter&.close
  gather&.close
end

puts

# --- REQ/REP vs CLIENT/SERVER ---

puts "--- Request/Reply: REQ/REP vs CLIENT/SERVER ---"

Async do |task|
  OMQ::Transport::Inproc.reset!

  rep = OMQ::REP.bind("inproc://bench_rep")
  req = OMQ::REQ.connect("inproc://bench_rep")
  rep_task = task.async do
    loop do
      msg = rep.receive
      rep << msg
    end
  end
  100.times do
    req << PAYLOAD
    req.receive
  end

  server = OMQ::SERVER.bind("inproc://bench_server")
  client = OMQ::CLIENT.connect("inproc://bench_server")
  server_task = task.async do
    loop do
      msg = server.receive
      server.send_to(msg[0], msg[1])
    end
  end
  100.times do
    client << PAYLOAD
    client.receive
  end

  Benchmark.ips do |x|
    x.config(warmup: 1, time: 3)
    x.report("REQ/REP") do
      req << PAYLOAD
      req.receive
    end
    x.report("CLIENT/SERVER") do
      client << PAYLOAD
      client.receive
    end
    x.compare!
  end

  rep_task.stop
  server_task.stop
ensure
  req&.close
  rep&.close
  client&.close
  server&.close
end

puts

# --- PUB/SUB vs RADIO/DISH ---

puts "--- Publish: PUB/SUB vs RADIO/DISH ---"

Async do
  OMQ::Transport::Inproc.reset!

  pub = OMQ::PUB.bind("inproc://bench_pub")
  sub = OMQ::SUB.connect("inproc://bench_pub", subscribe: "t.")
  sleep 0.01
  50.times do
    pub << "t.#{PAYLOAD}"
    sub.receive
  end

  radio = OMQ::RADIO.bind("inproc://bench_radio")
  dish  = OMQ::DISH.connect("inproc://bench_radio", group: "t")
  sleep 0.01
  50.times do
    radio.publish("t", PAYLOAD)
    dish.receive
  end

  Benchmark.ips do |x|
    x.config(warmup: 1, time: 3)
    x.report("PUB/SUB") do
      pub << "t.#{PAYLOAD}"
      sub.receive
    end
    x.report("RADIO/DISH") do
      radio.publish("t", PAYLOAD)
      dish.receive
    end
    x.compare!
  end
ensure
  sub&.close
  pub&.close
  dish&.close
  radio&.close
end
