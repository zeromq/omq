# frozen_string_literal: true

$VERBOSE = nil

require_relative '../lib/omq'
require 'async'
require 'benchmark/ips'
require 'console'
Console.logger = Console::Logger.new(Console::Output::Null.new)

MSG_SIZES = [64, 256, 1024, 4096]
TRANSPORTS = {
  'inproc' => ->(tag) { "inproc://bench_tp_#{tag}" },
  'ipc'    => ->(tag) { "ipc:///tmp/omq_bench_tp_#{tag}.sock" },
  'tcp'    => ->(tag) { "tcp://127.0.0.1:#{9000 + tag.hash.abs % 1000}" },
}

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts

TRANSPORTS.each do |transport, addr_fn|
  puts "--- #{transport} (1 peer) ---"

  MSG_SIZES.each do |size|
    payload = 'x' * size
    addr = addr_fn.call("#{transport}_#{size}")

    Async do
      pull = OMQ::PULL.bind(addr)
      push = OMQ::PUSH.connect(addr)

      100.times do
        push << payload
        pull.receive
      end

      Benchmark.ips do |x|
        x.config(warmup: 1, time: 3)

        x.report("#{size}B") do
          push << payload
          pull.receive
        end
      end
    ensure
      push&.close
      pull&.close
    end
  end

  puts
  next if transport == 'inproc' # multi-peer inproc needs unique endpoints per pull

  puts "--- #{transport} (3 peers) ---"

  MSG_SIZES.each do |size|
    payload = 'x' * size
    addr = addr_fn.call("#{transport}_multi_#{size}")

    Async do
      push = OMQ::PUSH.bind(addr)
      pulls = 3.times.map { OMQ::PULL.connect(addr) }
      wait_connected = pulls.map { |p| p.peer_connected }
      wait_connected.each(&:wait)

      # Warm up
      300.times { push << payload }
      pulls.each { |p| p.read_timeout = 0.02 }
      pulls.each do |p|
        loop { p.receive } rescue nil
      end

      Benchmark.ips do |x|
        x.config(warmup: 1, time: 3)

        x.report("#{size}B") do |n|
          (n / 3).times do
            3.times { push << payload }
            pulls.each { |p| p.receive }
          end
        end
      end
    ensure
      pulls&.each(&:close)
      push&.close
    end
  end

  puts
end

# -- inproc multi-peer --

puts "--- inproc (3 peers) ---"

MSG_SIZES.each do |size|
  payload = 'x' * size

  Async do
    OMQ::Transport::Inproc.reset!
    push = OMQ::PUSH.bind("inproc://bench_tp_inproc_multi_#{size}")
    pulls = 3.times.map { OMQ::PULL.connect("inproc://bench_tp_inproc_multi_#{size}") }

    # Warm up
    300.times { push << payload }
    pulls.each { |p| p.read_timeout = 0.02 }
    pulls.each do |p|
      loop { p.receive } rescue nil
    end

    Benchmark.ips do |x|
      x.config(warmup: 1, time: 3)

      x.report("#{size}B") do |n|
        (n / 3).times do
          3.times { push << payload }
          pulls.each { |p| p.receive }
        end
      end
    end
  ensure
    pulls&.each(&:close)
    push&.close
  end
end

puts
