# frozen_string_literal: true

# Benchmark: fan-out/fan-in with CPU work
#
# Compares: Async fibers (1 thread) vs Ractors (true parallelism)
#
# Topology:  producer → PUSH/PULL → N workers → PUSH/PULL → collector
# Each worker computes fib(28) per message (~2 ms of CPU work).
#
# Async workers share one thread — CPU work is sequential.
# Ractor workers run on separate threads — CPU work is parallel.
#
# Run:
#   ruby --yjit bench/ractors_vs_async/bench.rb async
#   ruby --yjit bench/ractors_vs_async/bench.rb ractors

$VERBOSE = nil
$stdout.sync = true

require_relative "../../../lib/omq"
require "async"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

N_WORKERS  = 4
N_MESSAGES = 1000

def fib(n) = n < 2 ? n : fib(n - 1) + fib(n - 2)

jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled? ? "+YJIT" : "no JIT"
puts "OMQ #{OMQ::VERSION} | Ruby #{RUBY_VERSION} (#{jit})"
puts "Fan-out: producer → #{N_WORKERS} workers×fib(28) → collector"
puts "#{N_MESSAGES} messages, 64 B each"
puts

PAYLOAD = ("x" * 64).freeze

case ARGV[0]
when "async"
  Async do |task|
    work_addr   = "ipc:///tmp/omq_bench_work_#{$$}.sock"
    result_addr = "ipc:///tmp/omq_bench_result_#{$$}.sock"

    producer  = OMQ::PUSH.bind(work_addr)
    collector = OMQ::PULL.bind(result_addr)

    # Workers
    workers = N_WORKERS.times.map do
      task.async do
        pull = OMQ::PULL.connect(work_addr)
        push = OMQ::PUSH.connect(result_addr)
        loop do
          msg = pull.receive
          fib(28)
          push << msg
        end
      ensure
        pull&.close
        push&.close
      end
    end

    # Warm up
    20.times do
      producer << PAYLOAD
      collector.receive
    end

    # Timed run
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    task.async { N_MESSAGES.times { producer << PAYLOAD } }
    N_MESSAGES.times { collector.receive }

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    rate    = N_MESSAGES / elapsed

    puts "async  (ipc, 1 thread):  %7.1f msg/s  (%5.0f ms)" % [rate, elapsed * 1000]
  ensure
    workers&.each(&:stop)
    producer&.close
    collector&.close
  end

when "ractors"
  tag         = "omq_bench_#{$$}"
  work_addr   = "ipc://@#{tag}_work"
  result_addr = "ipc://@#{tag}_result"

  Async do |task|
    # Bind first so workers can connect immediately
    producer  = OMQ::PUSH.bind(work_addr)
    collector = OMQ::PULL.bind(result_addr)

    workers = N_WORKERS.times.map do |i|
      Ractor.new(work_addr, result_addr) do |wa, ra|
        Console.logger = Console::Logger.new(Console::Output::Null.new)
        w = Module.new do
          module_function

          def fib(n) = n < 2 ? n : fib(n - 1) + fib(n - 2)
        end
        Async do
          pull = OMQ::PULL.connect(wa)
          push = OMQ::PUSH.connect(ra)
          loop do
            msg = pull.receive
            w.fib(28)
            push << msg
          end
        ensure
          pull&.close
          push&.close
        end
      end
    end

    sleep 0.3 # let workers connect

    # Warm up
    20.times do
      producer << PAYLOAD
      collector.receive
    end

    # Timed run
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    task.async { N_MESSAGES.times { producer << PAYLOAD } }
    N_MESSAGES.times { collector.receive }

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    rate    = N_MESSAGES / elapsed

    puts "ractors (ipc, #{N_WORKERS} threads): %7.1f msg/s  (%5.0f ms)" % [rate, elapsed * 1000]
  ensure
    producer&.close
    collector&.close
  end
  exit!(true)

else
  abort "Usage: ruby --yjit #{$0} [async|ractors]"
end
