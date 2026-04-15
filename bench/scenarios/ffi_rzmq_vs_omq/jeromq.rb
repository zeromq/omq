# frozen_string_literal: true

# PUSH/PULL + REQ/REP throughput on JeroMQ (JRuby).
# Counterparts: omq.rb, ffi_rzmq.rb, cztop.rb, pyzmq.py.
#
# Usage: jruby bench/scenarios/ffi_rzmq_vs_omq/jeromq.rb

$stdout.sync = true

raise "this script requires JRuby" unless RUBY_PLATFORM == "java"

require "java"
require_relative "../jeromq_vs_omq/vendor/jeromq-0.6.0.jar"

java_import "org.zeromq.ZContext"
java_import "org.zeromq.SocketType"

System = java.lang.System

SIZES  = [128, 1024]
N      = 1_000_000
WARMUP = 10_000


def bench_push_pull(ctx, size)
  payload = ("x" * size).to_java_bytes

  pull = ctx.createSocket(SocketType::PULL)
  pull.bind("tcp://127.0.0.1:*")
  ep = pull.getLastEndpoint

  push = ctx.createSocket(SocketType::PUSH)
  push.connect(ep)

  producer = Thread.new do
    (WARMUP + N).times { push.send(payload, 0) }
  end

  WARMUP.times { pull.recv(0) }

  t0 = System.nano_time
  N.times { pull.recv(0) }
  elapsed = (System.nano_time - t0) / 1e9

  producer.join
  ctx.destroySocket(push)
  ctx.destroySocket(pull)

  rate = N / elapsed
  mbps = rate * size / 1_000_000.0
  printf "  PUSH/PULL %5dB  %10.1f msg/s  %9.1f MB/s  (%.2fs, n=%d)\n",
         size, rate, mbps, elapsed, N
end


def bench_req_rep(ctx, size)
  payload = ("x" * size).to_java_bytes
  rounds  = 100_000

  rep = ctx.createSocket(SocketType::REP)
  rep.bind("tcp://127.0.0.1:*")
  ep = rep.getLastEndpoint

  req = ctx.createSocket(SocketType::REQ)
  req.connect(ep)

  server = Thread.new do
    loop do
      msg = rep.recv(0)
      break if msg.nil?
      rep.send(msg, 0)
    end
  rescue org.zeromq.ZMQException, java.nio.channels.ClosedChannelException
    nil
  end

  1000.times do
    req.send(payload, 0)
    req.recv(0)
  end

  t0 = System.nano_time
  rounds.times do
    req.send(payload, 0)
    req.recv(0)
  end
  elapsed = (System.nano_time - t0) / 1e9

  ctx.destroySocket(req)
  ctx.destroySocket(rep)

  rate   = rounds / elapsed
  lat_us = elapsed / rounds * 1_000_000
  printf "  REQ/REP   %5dB  %10.1f rtt/s  %8.1f µs/rtt  (%.2fs, n=%d)\n",
         size, rate, lat_us, elapsed, rounds
end


jeromq_version = Java::OrgZeromq::ZMQ.getVersionString rescue "unknown"
puts "JeroMQ #{jeromq_version} | #{RUBY_DESCRIPTION.split(')').first})"
puts "--- JRuby + JeroMQ (JVM threads, pure Java, tcp loopback) ---"

ctx = ZContext.new
begin
  SIZES.each { bench_push_pull(ctx, it) }
  SIZES.each { bench_req_rep(ctx, it) }
ensure
  ctx.close
end
