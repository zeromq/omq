# frozen_string_literal: true

# PUSH/PULL throughput on JeroMQ (JRuby).
# Counterpart: omq.rb (MRI + OMQ).
#
# Usage: jruby bench/scenarios/jeromq_vs_omq/jeromq.rb
#
# Pulls jeromq from Maven Central via jar-dependencies on first run.

$stdout.sync = true

raise "this script requires JRuby" unless RUBY_PLATFORM == "java"

require "java"
require_relative "vendor/jeromq-0.6.0.jar"

java_import "org.zeromq.ZContext"
java_import "org.zeromq.SocketType"

SIZES  = [128, 1024]
N      = 1_000_000
WARMUP = 10_000


def bench(ctx, size)
  payload = ("x" * size).to_java_bytes

  pull = ctx.createSocket(SocketType::PULL)
  pull.bind("tcp://127.0.0.1:*")
  ep = pull.getLastEndpoint

  push = ctx.createSocket(SocketType::PUSH)
  push.connect(ep)

  producer = Thread.new do
    WARMUP.times { push.send(payload, 0) }
    N.times      { push.send(payload, 0) }
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
  printf "  %5dB  %10.1f msg/s  %9.1f MB/s  (%.2fs, n=%d)\n", size, rate, mbps, elapsed, N
end


System = java.lang.System
jeromq_version = Java::OrgZeromq::ZMQ.getVersionString rescue "unknown"

puts "PUSH/PULL | JeroMQ #{jeromq_version} | #{RUBY_DESCRIPTION.split(')').first})"
puts "--- JRuby + JeroMQ (JVM threads, tcp loopback) ---"

ctx = ZContext.new
begin
  SIZES.each { bench(ctx, it) }
ensure
  ctx.close
end
