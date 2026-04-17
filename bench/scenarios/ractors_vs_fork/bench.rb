# frozen_string_literal: true

# Benchmark: parallel compute pipeline
#
# Compares two approaches to CPU-parallel work distribution:
#
#   fork + OMQ  — forked worker processes communicating via IPC sockets
#   Ractors     — Ractor workers communicating via Ractor::Port
#
# Topology:  producer → N workers×fib(28) → collector
# Each worker receives a number, computes fib(n), and sends back the
# Marshal'd result.
#
# Run:
#   ruby --yjit bench/ractors_vs_fork/bench.rb fork
#   ruby --yjit bench/ractors_vs_fork/bench.rb ractors

$VERBOSE = nil
$stdout.sync = true

N_WORKERS  = 4
N_MESSAGES = 1000
FIB_N      = 28 # ~2 ms per call

def fib(n) = n < 2 ? n : fib(n - 1) + fib(n - 2)

jit = if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? then "+YJIT" else "no JIT" end
puts "Ruby #{RUBY_VERSION} (#{jit})"
puts "Fan-out: producer → #{N_WORKERS} workers×fib(#{FIB_N}) → collector"
puts "#{N_MESSAGES} tasks"
puts

case ARGV[0]
when "fork"
  require_relative "../../../lib/omq"
  require "async"
  require "console"
  Console.logger = Console::Logger.new(Console::Output::Null.new)

  work_addr   = "ipc:///tmp/omq_bench_fork_work_#{$$}.sock"
  result_addr = "ipc:///tmp/omq_bench_fork_result_#{$$}.sock"

  pids = N_WORKERS.times.map do
    fork do
      Console.logger = Console::Logger.new(Console::Output::Null.new)
      Async do
        pull = OMQ::PULL.connect(work_addr)
        push = OMQ::PUSH.connect(result_addr)
        loop do
          n = Marshal.load(pull.receive.first)
          push << Marshal.dump(fib(n))
        end
      ensure
        pull&.close
        push&.close
      end
    end
  end

  Async do |task|
    producer  = OMQ::PUSH.bind(work_addr)
    collector = OMQ::PULL.bind(result_addr)

    sleep 0.3

    # Warm up
    50.times do
      producer << Marshal.dump(FIB_N)
      collector.receive
    end

    # Timed run
    results = nil
    elapsed = Async::Clock.measure do
      task.async { N_MESSAGES.times { producer << Marshal.dump(FIB_N) } }
      results = N_MESSAGES.times.map { Marshal.load(collector.receive.first) }
    end
    rate    = N_MESSAGES / elapsed

    puts "fork + OMQ (#{N_WORKERS} processes): %7.1f tasks/s  (%5.0f ms)" % [rate, elapsed * 1000]
    puts "  sample: #{results.first(3).inspect}"
  ensure
    pids&.each { |pid| Process.kill(:TERM, pid) rescue nil }
    pids&.each { |pid| Process.wait(pid) rescue nil }
    producer&.close
    collector&.close
  end

when "ractors"
  result_port = Ractor::Port.new

  workers = N_WORKERS.times.map do
    Ractor.new(result_port) do |rp|
      f = Module.new do
        module_function

        def fib(n) = n < 2 ? n : fib(n - 1) + fib(n - 2)
      end
      loop do
        n = Ractor.receive
        break if n == :stop
        rp.send(f.fib(n))
      end
    end
  end

  # Warm up
  50.times do
    workers.each { |w| w.send(FIB_N) }
    (N_WORKERS * 1).times { result_port.receive }
  end

  # Timed run
  results = nil
  elapsed = Async::Clock.measure do
    sender = Thread.new do
      N_MESSAGES.times do |i|
        workers[i % N_WORKERS].send(FIB_N)
      end
    end

    results = N_MESSAGES.times.map { result_port.receive }
    sender.join
  end
  rate    = N_MESSAGES / elapsed

  puts "Ractor::Port (#{N_WORKERS} ractors):  %7.1f tasks/s  (%5.0f ms)" % [rate, elapsed * 1000]
  puts "  sample: #{results.first(3).inspect}"

  workers.each { |w| w.send(:stop) }
  workers.each { |w| w.join rescue nil }

else
  abort "Usage: ruby --yjit #{$0} [fork|ractors]"
end
