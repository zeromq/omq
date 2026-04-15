# frozen_string_literal: true

# PUSH/PULL + REQ/REP throughput on MRI + ffi-rzmq → libzmq.
# Counterpart: omq.rb (MRI + OMQ, pure Ruby).
#
# Usage: ruby --yjit bench/scenarios/ffi_rzmq_vs_omq/ffi_rzmq.rb

$stdout.sync = true

require "ffi-rzmq"

SIZES  = [128, 1024]
N      = 1_000_000
WARMUP = 10_000

CTX = ZMQ::Context.new


def bind_ephemeral(sock)
  rc = sock.bind("tcp://127.0.0.1:*")
  raise "bind failed" unless rc == 0 || rc.nil?
  ep = String.new
  sock.getsockopt(ZMQ::LAST_ENDPOINT, ep)
  ep.sub(/\0\z/, "")
end


def bench_push_pull(size)
  payload = ("x" * size).b.freeze

  pull = CTX.socket(ZMQ::PULL)
  pull.setsockopt(ZMQ::RCVHWM, 1000)
  ep = bind_ephemeral(pull)

  push = CTX.socket(ZMQ::PUSH)
  push.setsockopt(ZMQ::SNDHWM, 1000)
  push.connect(ep)

  producer = Thread.new do
    (WARMUP + N).times { push.send_string(payload) }
  end

  buf = String.new
  WARMUP.times { pull.recv_string(buf) }

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  N.times { pull.recv_string(buf) }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

  producer.join
  push.close
  pull.close

  rate = N / elapsed
  mbps = rate * size / 1_000_000.0
  printf "  PUSH/PULL %5dB  %10.1f msg/s  %9.1f MB/s  (%.2fs, n=%d)\n",
         size, rate, mbps, elapsed, N
end


def bench_req_rep(size)
  payload = ("x" * size).b.freeze
  rounds  = 100_000

  rep = CTX.socket(ZMQ::REP)
  ep  = bind_ephemeral(rep)

  req = CTX.socket(ZMQ::REQ)
  req.connect(ep)

  server = Thread.new do
    buf = String.new
    loop do
      rc = rep.recv_string(buf)
      break if rc < 0
      rep.send_string(buf)
    end
  end

  buf = String.new
  1000.times do
    req.send_string(payload)
    req.recv_string(buf)
  end

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  rounds.times do
    req.send_string(payload)
    req.recv_string(buf)
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

  req.close
  rep.close
  server.kill rescue nil
  server.join rescue nil

  rate   = rounds / elapsed
  lat_us = elapsed / rounds * 1_000_000
  printf "  REQ/REP   %5dB  %10.1f rtt/s  %8.1f µs/rtt  (%.2fs, n=%d)\n",
         size, rate, lat_us, elapsed, rounds
end


puts "ffi-rzmq #{Gem.loaded_specs['ffi-rzmq'].version} → libzmq | #{RUBY_DESCRIPTION.split(')').first})"
puts "--- MRI + ffi-rzmq (FFI → libzmq, tcp loopback) ---"
SIZES.each { bench_push_pull(it) }
SIZES.each { bench_req_rep(it) }

CTX.terminate
