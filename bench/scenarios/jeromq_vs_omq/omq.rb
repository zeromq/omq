# frozen_string_literal: true

# PUSH/PULL throughput on OMQ (MRI).
# Counterpart: jeromq.rb (JRuby + JeroMQ).
#
# Usage: bundle exec ruby --yjit bench/scenarios/jeromq_vs_omq/omq.rb

$stdout.sync = true

require "bundler/setup"
require "omq"
require "async"

SIZES = [128, 1024]
N     = 1_000_000
WARMUP = 10_000


def bench(size)
  payload = ("x" * size).b.freeze

  Sync do
    pull = OMQ::PULL.new
    pull.bind("tcp://127.0.0.1:0")
    ep = "tcp://127.0.0.1:#{pull.last_tcp_port}"

    push = OMQ::PUSH.new
    push.connect(ep)

    producer = Async do
      WARMUP.times { push << payload }
      N.times      { push << payload }
    end

    WARMUP.times { pull.receive }

    t0 = Async::Clock.now
    N.times { pull.receive }
    elapsed = Async::Clock.now - t0

    producer.wait
    push.close
    pull.close

    rate = N / elapsed
    mbps = rate * size / 1_000_000.0
    printf "  %5dB  %10.1f msg/s  %9.1f MB/s  (%.2fs, n=%d)\n", size, rate, mbps, elapsed, N
  end
end


puts "PUSH/PULL | OMQ #{OMQ::VERSION} | #{RUBY_DESCRIPTION.split(')').first})"
puts "--- MRI + OMQ (Async fibers, tcp loopback) ---"
SIZES.each { bench(it) }
