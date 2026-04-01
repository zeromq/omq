# frozen_string_literal: true

# Measures sustained PUSH/PULL pipeline throughput in MB/s.

$VERBOSE = nil
$stdout.sync = true

require_relative '../lib/omq'
require 'async'
require 'console'
Console.logger = Console::Logger.new(Console::Output::Null.new)

N     = 100_000
SIZES = [64, 256, 1024, 4096, 65_536]

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts "#{N} messages per run"
puts

def measure(pull, pushes, payload, n)
  per_push = n / pushes.size

  # Warm up
  100.times { pushes.first << payload; pull.receive }

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  senders = pushes.map do |push|
    Async { per_push.times { push << payload } }
  end

  (per_push * pushes.size).times { pull.receive }
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  senders.each(&:wait)

  total_bytes = n * payload.bytesize
  mbps        = total_bytes / elapsed / 1_000_000.0
  msgs_s      = n / elapsed
  printf "  %6s  %8.1f MB/s  %8.0f msg/s  (%.2fs)\n",
         "#{payload.bytesize}B", mbps, msgs_s, elapsed
end

# -- inproc ----------------------------------------------------------------

seq = 0

[1, 3].each do |peers|
  puts "--- inproc (#{peers} peer#{'s' if peers > 1}) ---"
  SIZES.each do |size|
    seq += 1
    Async do
      OMQ::Transport::Inproc.reset!
      ep   = "inproc://mbps-#{seq}"
      pull = OMQ::PULL.bind(ep)
      pushes = peers.times.map { OMQ::PUSH.connect(ep) }
      measure(pull, pushes, 'x' * size, N)
    ensure
      pushes&.each(&:close)
      pull&.close
    end
  end
  puts
end

# -- ipc -------------------------------------------------------------------

[1, 3].each do |peers|
  puts "--- ipc (#{peers} peer#{'s' if peers > 1}) ---"
  SIZES.each do |size|
    seq += 1
    Async do
      ep   = "ipc://@omq-mbps-#{seq}"
      pull = OMQ::PULL.bind(ep)
      pushes = peers.times.map { OMQ::PUSH.connect(ep) }
      pushes.each { |p| p.peer_connected.wait }
      measure(pull, pushes, 'x' * size, N)
    ensure
      pushes&.each(&:close)
      pull&.close
    end
  end
  puts
end

# -- tcp -------------------------------------------------------------------

[1, 3].each do |peers|
  puts "--- tcp (#{peers} peer#{'s' if peers > 1}) ---"
  SIZES.each do |size|
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port
      pushes = peers.times.map { OMQ::PUSH.connect("tcp://127.0.0.1:#{port}") }
      pushes.each { |p| p.peer_connected.wait }
      measure(pull, pushes, 'x' * size, N)
    ensure
      pushes&.each(&:close)
      pull&.close
    end
  end
  puts
end
