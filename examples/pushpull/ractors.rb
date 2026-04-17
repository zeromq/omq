# frozen_string_literal: true

# Push/Pull across Ractors using TCP.
#
# Each worker Ractor runs its own Async reactor and PULL socket.
# The main Ractor pushes work items and collects results.

$VERBOSE = nil

require_relative "../../lib/omq"
require "async"
require "console"

NUM_WORKERS = 4
NUM_TASKS   = 20

workers = NUM_WORKERS.times.map do |id|
  Ractor.new(id) do |wid|
    # Silence console logger inside Ractor (avoids JSON Ractor isolation issue)
    Console.logger = Console::Logger.new(Console::Output::Null.new)

    work_addr   = Ractor.receive
    result_addr = Ractor.receive

    Async do
      pull = OMQ::PULL.connect(work_addr)
      push = OMQ::PUSH.connect(result_addr)

      loop do
        msg   = pull.receive.first
        reply = "worker-#{wid}: #{msg.upcase}"
        push << reply
      end
    ensure
      pull&.close
      push&.close
    end
  end
end

Console.logger = Console::Logger.new(Console::Output::Null.new)

Async do
  push = OMQ::PUSH.new
  work_port = push.bind("tcp://127.0.0.1:0").port

  pull = OMQ::PULL.new
  result_port = pull.bind("tcp://127.0.0.1:0").port

  # Tell workers where to connect
  workers.each do |w|
    w.send("tcp://127.0.0.1:#{work_port}")
    w.send("tcp://127.0.0.1:#{result_port}")
  end

  # Wait for workers to connect
  sleep 0.3

  # Send work
  NUM_TASKS.times do |i|
    push << "task-#{i}"
  end
  puts "Sent #{NUM_TASKS} tasks to #{NUM_WORKERS} Ractors"
  puts

  # Collect results
  NUM_TASKS.times do
    msg = pull.receive.first
    puts "  ← #{msg}"
  end

  puts
  puts "Done!"
ensure
  push&.close
  pull&.close
end
