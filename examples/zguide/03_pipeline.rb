#!/usr/bin/env ruby
# frozen_string_literal: true

$VERBOSE = nil
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))

require 'minitest/autorun'
require 'minitest/spec'
require 'omq'
require 'async'
require 'console'
Console.logger = Console::Logger.new(Console::Output::Null.new)

# ZGuide Chapter 1 — Pipeline (Divide and Conquer)
# A ventilator pushes work items to workers via PUSH/PULL.
# Workers process items and push results to a sink.
# Demonstrates fan-out/fan-in with load balancing across workers.

describe 'Pipeline' do
  it 'distributes work across multiple workers and collects results' do
    vent_ep = 'inproc://zg03_vent'
    sink_ep = 'inproc://zg03_sink'
    n_tasks   = 1000
    n_workers = 3
    results   = []
    worker_counts = Hash.new(0)

    Async do |task|
      # Sink
      sink = OMQ::PULL.bind(sink_ep)
      sink.recv_timeout = 2

      sink_task = task.async do
        n_tasks.times do
          msg = sink.receive.first
          results << msg
          worker_id = msg.split(':').first
          worker_counts[worker_id] += 1
        end
      end

      # Ventilator
      vent = OMQ::PUSH.bind(vent_ep)

      # Workers — create the sockets up front so we can wait on each
      # one's peer_connected promise before the ventilator starts
      # sending. PUSH work-stealing batches eagerly on inproc, so if
      # we let the vent flood while only worker-0 has attached, it
      # will drain the entire queue before its siblings show up.
      worker_sockets = n_workers.times.map do |id|
        pull = OMQ::PULL.connect(vent_ep)
        push = OMQ::PUSH.connect(sink_ep)
        pull.recv_timeout = 2
        [id, pull, push]
      end

      barrier = Async::Barrier.new
      worker_sockets.each do |_, pull, push|
        barrier.async { pull.peer_connected.wait }
        barrier.async { push.peer_connected.wait }
      end
      barrier.wait

      workers = worker_sockets.map do |id, pull, push|
        task.async do
          loop do
            t = pull.receive.first
            break if t == 'END'
            push << "worker-#{id}:#{t}"
          rescue IO::TimeoutError
            break
          end
        ensure
          pull.close
          push.close
        end
      end

      # Send enough tasks to exceed one worker pump's batch cap
      # (256 messages). PUSH is work-stealing — the first pump to
      # wake grabs a whole batch — so to see all workers participate
      # we need more messages than one batch can hold.
      n_tasks.times { |i| vent << "task-#{i}" }
      n_workers.times { vent << 'END' }

      sink_task.wait
      workers.each(&:wait)

      assert_equal n_tasks, results.size
      assert(worker_counts.size > 1, 'expected multiple workers to participate')
      puts "  summary: #{results.size} results from #{worker_counts.size} workers"
      worker_counts.each { |id, count| puts "    #{id}: #{count} items" }
    ensure
      sink&.close
      vent&.close
    end
  end
end
