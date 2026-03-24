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

# ZGuide Chapter 1 — Request-Reply
# Basic REQ/REP echo, then a multi-worker broker using ROUTER/DEALER.
# Demonstrates the fundamental request-reply pattern and how to scale
# it with a broker that load-balances across workers.

describe 'Request-Reply' do
  it 'echoes messages between REQ and REP' do
    endpoint = 'inproc://zg01_basic'

    Async do |task|
      rep = OMQ::REP.bind(endpoint)
      req = OMQ::REQ.connect(endpoint)

      server = task.async do
        3.times do
          msg = rep.receive
          rep << "echo:#{msg.first}"
        end
      end

      replies = 3.times.map do |i|
        req << "hello-#{i}"
        reply = req.receive.first
        puts "  client: hello-#{i} -> #{reply}"
        reply
      end

      server.wait
      assert_equal %w[echo:hello-0 echo:hello-1 echo:hello-2], replies
    ensure
      req&.close
      rep&.close
    end
  end


  it 'brokers requests across multiple workers via ROUTER/DEALER' do
    frontend_ep = 'inproc://zg01_frontend'
    backend_ep  = 'inproc://zg01_backend'
    n_workers   = 3
    n_requests  = 9
    worker_ids  = []
    mu          = Mutex.new

    Async do |task|
      # Broker: ROUTER (frontend) <-> DEALER (backend)
      frontend = OMQ::ROUTER.bind(frontend_ep)
      backend  = OMQ::DEALER.bind(backend_ep)

      fwd = task.async { n_requests.times { backend << frontend.receive } }
      ret = task.async { n_requests.times { frontend << backend.receive } }

      # Workers
      workers = n_workers.times.map do |id|
        task.async do
          rep = OMQ::REP.connect(backend_ep)
          rep.recv_timeout = 1
          loop do
            msg = rep.receive
            mu.synchronize { worker_ids << id }
            rep << "worker-#{id}:#{msg.first}"
            puts "  worker-#{id}: handled #{msg.first}"
          rescue IO::TimeoutError
            break
          end
        ensure
          rep.close
        end
      end

      # Client
      req = OMQ::REQ.connect(frontend_ep)
      req.recv_timeout = 1

      replies = n_requests.times.map do |i|
        req << "request-#{i}"
        reply = req.receive.first
        puts "  client: request-#{i} -> #{reply}"
        reply
      end

      fwd.wait
      ret.wait
      workers.each(&:wait)

      assert_equal n_requests, replies.size
      assert(worker_ids.uniq.size > 1, 'expected multiple workers to participate')
      puts "  summary: #{replies.size} replies from #{worker_ids.uniq.size} workers"
    ensure
      req&.close
      frontend&.close
      backend&.close
    end
  end
end
