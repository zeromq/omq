# frozen_string_literal: true

# Shared scaffolding for per-pattern throughput benchmarks.
#
# Usage:
#   require_relative '../bench_helper'
#   BenchHelper.run("PUSH/PULL", dir: __dir__) do |transport, ep, peers, payload, n|
#     # Set up sockets, measure, return { mbps:, msgs_s: }
#   end

$VERBOSE = nil
$stdout.sync = true

require "bundler/setup"
require_relative '../lib/omq'
require 'async'
require 'console'
require 'rbnacl'
require 'json'
require 'protocol/zmtp/mechanism/curve'
require 'omq/rfc/blake3zmq'
Console.logger = Console::Logger.new(Console::Output::Null.new)

module BenchHelper
  # Message count per size, tuned so the full 6-script benchmark suite
  # finishes in ~120s total with YJIT (5 transports × 2 peer counts).
  RUNS = {
    64     => 20_000,
    256    => 16_000,
    1024   => 12_000,
    4096   =>  8_000,
    16_384 =>  5_000,
    65_536 =>  3_000,
  }.freeze
  SIZES = RUNS.keys.freeze

  RESULTS_PATH = File.join(__dir__, "results.jsonl").freeze

  module_function

  KERNEL = `uname -r`.strip.freeze

  TRANSPORTS = %w[inproc ipc tcp curve blake3].freeze

  def run_id
    @run_id ||= ENV["OMQ_BENCH_RUN_ID"] || Time.now.strftime("%Y-%m-%dT%H:%M:%S")
  end

  # Per-size timeout in seconds. If a single benchmark run takes longer
  # than this, the benchmark aborts with an error instead of hanging.
  RUN_TIMEOUT = Integer(ENV.fetch("OMQ_BENCH_TIMEOUT", 30))

  def run(label, dir:, peer_counts: [1, 3], &block)
    pattern = File.basename(dir)
    jit     = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
    puts "#{label} | OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit}) | #{KERNEL}"
    puts

    seq = 0

    TRANSPORTS.each do |transport|
      peer_counts.each do |peers|
        header = "#{transport} (#{peers} peer#{'s' if peers > 1})"
        puts "--- #{header} ---"
        completed = 0
        SIZES.each do |size|
          n   = RUNS[size]
          seq += 1
          Async do |task|
            task.with_timeout(RUN_TIMEOUT) do
              OMQ::Transport::Inproc.reset! if transport == "inproc"
              ep = endpoint(transport, seq)
              r  = block.call(transport, ep, peers, "x" * size, n)
              append_result(pattern, transport, peers, size, n, r[:elapsed], r[:mbps], r[:msgs_s])
              completed += 1
            end
          rescue Async::TimeoutError
            abort "BENCH TIMEOUT: #{header} #{size}B exceeded #{RUN_TIMEOUT}s"
          end
        end
        if completed == 0
          abort "BENCH FAILED: #{header} produced no results"
        end
        puts
      end
    end
  end

  def endpoint(transport, seq)
    case transport
    when "inproc"
      "inproc://bench-#{seq}"
    when "ipc"
      "ipc://@omq-bench-#{seq}"
    when "tcp"
      "tcp://127.0.0.1:0"
    when "curve"
      "tcp://127.0.0.1:0"
    when "blake3"
      "tcp://127.0.0.1:0"
    end
  end

  # Returns the resolved endpoint after bind (handles port auto-selection).
  #
  def resolve_endpoint(transport, socket)
    case transport
    when "tcp", "curve", "blake3"
      "tcp://127.0.0.1:#{socket.last_tcp_port}"
    else socket.last_endpoint
    end
  end

  # Applies transport-specific security (CURVE mechanism).
  #
  def apply_security(socket, transport, role:)
    case transport
    when "curve"
      socket.mechanism = curve_mechanism(role)
    when "blake3"
      socket.mechanism = blake3_mechanism(role)
    end
  end

  def curve_mechanism(role)
    @curve_keys ||= begin
      server_sec = RbNaCl::PrivateKey.generate
      { server_pub: server_sec.public_key.to_s, server_sec: server_sec.to_s }
    end
    k = @curve_keys
    case role
    when :server
      Protocol::ZMTP::Mechanism::Curve.server(public_key: k[:server_pub], secret_key: k[:server_sec], crypto: RbNaCl)
    when :client
      Protocol::ZMTP::Mechanism::Curve.client(server_key: k[:server_pub], crypto: RbNaCl)
    end
  end

  def blake3_mechanism(role)
    k = @curve_keys  # same X25519 keys
    case role
    when :server
      Protocol::ZMTP::Mechanism::Blake3.server(public_key: k[:server_pub], secret_key: k[:server_sec])
    when :client
      Protocol::ZMTP::Mechanism::Blake3.client(server_key: k[:server_pub])
    end
  end

  def measure(receiver, senders, payload, n)
    per_sender = n / senders.size

    # Warm up
    100.times do
      senders.first << payload
      receiver.receive
    end

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    barrier = Async::Barrier.new
    senders.each do |s|
      barrier.async { per_sender.times { s << payload } }
    end

    (per_sender * senders.size).times { receiver.receive }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    barrier.wait

    report(payload.bytesize, n, elapsed)
  end

  def measure_roundtrip(requester, responder_task, payload, n)
    # Warm up
    100.times do
      requester << payload
      requester.receive
    end

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    n.times do
      requester << payload
      requester.receive
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

    report(payload.bytesize, n, elapsed)
  end

  def report(msg_size, n, elapsed)
    mbps   = n * msg_size / elapsed / 1_000_000.0
    msgs_s = n / elapsed
    printf "  %6s  %8.1f MB/s  %8.0f msg/s  (%.2fs)\n",
           "#{msg_size}B", mbps, msgs_s, elapsed
    { elapsed: elapsed, mbps: mbps, msgs_s: msgs_s }
  end

  def wait_connected(*sockets)
    sockets.flatten.each { |s| s.peer_connected.wait }
  end

  # Waits until every SUB has an active subscription at the PUB by
  # sending probe messages until each sub receives one.
  #
  def wait_subscribed(pub, subs)
    pending = subs.to_set
    until pending.empty?
      pub << ""
      pending.each do |sub|
        begin
          Async::Task.current.with_timeout(0.01) { sub.receive }
          pending.delete(sub)
        rescue Async::TimeoutError
          # subscription not yet propagated
        end
      end
    end
  end

  def append_result(pattern, transport, peers, msg_size, msg_count, elapsed, mbps, msgs_s)
    row = {
      run_id:  run_id,
      pattern: pattern,
      transport: transport,
      peers:     peers,
      msg_size:  msg_size,
      msg_count: msg_count,
      elapsed_s: elapsed.round(6),
      mbps:      mbps.round(2),
      msgs_s:    msgs_s.round(1),
    }
    File.open(RESULTS_PATH, "a") { |f| f.puts(JSON.generate(row)) }
  end
end
