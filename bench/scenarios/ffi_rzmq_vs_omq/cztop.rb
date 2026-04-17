# frozen_string_literal: true

# PUSH/PULL + REQ/REP throughput on MRI + CZTop → CZMQ → libzmq.
# Counterparts: omq.rb (pure Ruby OMQ), ffi_rzmq.rb (ffi-rzmq).
#
# Usage: ruby --yjit bench/scenarios/ffi_rzmq_vs_omq/cztop.rb

$stdout.sync = true

require "cztop"
require "async/clock"

SIZES  = [128, 1024]
N      = 1_000_000
WARMUP = 10_000


def bench_push_pull(size)
  payload = ("x" * size).b.freeze

  pull = CZTop::Socket::PULL.new("tcp://127.0.0.1:*")
  ep   = pull.last_endpoint

  push = CZTop::Socket::PUSH.new(">#{ep}")

  producer = Thread.new do
    (WARMUP + N).times { push << payload }
  end

  WARMUP.times { pull.receive }

  elapsed = Async::Clock.measure do
    N.times { pull.receive }
  end

  producer.join

  rate = N / elapsed
  mbps = rate * size / 1_000_000.0
  printf "  PUSH/PULL %5dB  %10.1f msg/s  %9.1f MB/s  (%.2fs, n=%d)\n",
         size, rate, mbps, elapsed, N
end


def bench_req_rep(size)
  payload = ("x" * size).b.freeze
  rounds  = 100_000

  rep = CZTop::Socket::REP.new("tcp://127.0.0.1:*")
  ep  = rep.last_endpoint

  req = CZTop::Socket::REQ.new(">#{ep}")

  server = Thread.new do
    loop do
      rep << rep.receive
    end
  rescue Exception
    nil
  end

  1000.times do
    req << payload
    req.receive
  end

  elapsed = Async::Clock.measure do
    rounds.times do
      req << payload
      req.receive
    end
  end

  server.kill
  server.join rescue nil

  rate   = rounds / elapsed
  lat_us = elapsed / rounds * 1_000_000
  printf "  REQ/REP   %5dB  %10.1f rtt/s  %8.1f µs/rtt  (%.2fs, n=%d)\n",
         size, rate, lat_us, elapsed, rounds
end


puts "CZTop #{Gem.loaded_specs['cztop'].version} → CZMQ → libzmq | #{RUBY_DESCRIPTION.split(')').first})"
puts "--- MRI + CZTop (FFI → CZMQ → libzmq, tcp loopback) ---"
SIZES.each { bench_push_pull(it) }
SIZES.each { bench_req_rep(it) }
