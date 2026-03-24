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

# ZGuide Chapter 4 — Freelance Pattern
# Brokerless reliability: client talks directly to multiple servers.
# Three models demonstrated:
#   1. Sequential failover — try servers in order, skip on timeout
#   2. Shotgun — blast to all, take first reply
#   3. Tracked — remember which server is alive, prefer it

describe 'Freelance' do
  def start_server(task, endpoint, name, delay: 0)
    task.async do
      rep = OMQ::REP.bind(endpoint)
      rep.recv_timeout = 2
      loop do
        msg = rep.receive.first
        sleep delay if delay > 0
        rep << "#{name}:#{msg}"
        puts "  #{name}: served #{msg}"
      rescue IO::TimeoutError
        break
      end
    ensure
      rep.close
    end
  end


  it 'model 1: sequential failover on timeout' do
    ep1 = 'inproc://zg11a_server1'
    ep2 = 'inproc://zg11a_server2'
    ep3 = 'inproc://zg11a_server3'

    Async do |task|
      s2 = start_server(task, ep2, 'server2')
      sleep 0.01

      replies = 3.times.map do |i|
        reply = nil
        endpoints = [ep1, ep2, ep3]
        endpoints.each do |ep|
          req = OMQ::REQ.connect(ep)
          req.recv_timeout = 0.15

          req << "request-#{i}"
          begin
            reply = req.receive.first
            req.close
            break
          rescue IO::TimeoutError
            puts "  client: timeout on #{ep}, trying next"
            req.close
          end
        end
        reply
      end

      s2.stop

      assert(replies.all? { |r| r&.start_with?('server2:') }, 'all should come from server2')
      puts "  summary: #{replies.size} requests, all served by server2 after failover"
    end
  end


  it 'model 2: shotgun — blast to all, take first reply' do
    ep1 = 'inproc://zg11b_server1'
    ep2 = 'inproc://zg11b_server2'

    Async do |task|
      s1 = start_server(task, ep1, 'fast', delay: 0)
      s2 = start_server(task, ep2, 'slow', delay: 0.3)
      sleep 0.01

      dealer = OMQ::DEALER.new
      dealer.connect(ep1)
      dealer.connect(ep2)
      dealer.recv_timeout = 1

      dealer << ['', 'shotgun-req']
      dealer << ['', 'shotgun-req']

      reply = dealer.receive
      first_reply = reply.last
      puts "  client: first reply = #{first_reply}"
      dealer.close

      s1.stop
      s2.stop

      assert first_reply.end_with?('shotgun-req')
      assert first_reply.start_with?('fast:'), "expected fast server first, got: #{first_reply}"
    end
  end


  it 'model 3: tracked — remember which server is alive' do
    ep1 = 'inproc://zg11c_server1'
    ep2 = 'inproc://zg11c_server2'

    Async do |task|
      s1 = start_server(task, ep1, 'server1')
      s2 = start_server(task, ep2, 'server2')
      sleep 0.01

      known_good = nil
      endpoints = [ep1, ep2]

      replies = 6.times.map do |i|
        try_order = known_good ? [known_good] + (endpoints - [known_good]) : endpoints
        reply = nil

        try_order.each do |ep|
          req = OMQ::REQ.connect(ep)
          req.recv_timeout = 0.2

          req << "request-#{i}"
          begin
            reply = req.receive.first
            known_good = ep
            puts "  client: #{reply} (via #{ep})"
            req.close
            break
          rescue IO::TimeoutError
            puts "  client: #{ep} timed out, rotating"
            known_good = nil if known_good == ep
            req.close
          end
        end

        # Kill server1 after 3 requests
        if i == 2
          puts "  --- server1 goes down ---"
          s1.stop
        end

        reply
      end

      s2.stop

      assert_equal 6, replies.size
      early = replies[0..2]
      late  = replies[3..5]
      assert(early.any? { |r| r.start_with?('server1:') }, 'early requests should hit server1')
      assert(late.all? { |r| r.start_with?('server2:') }, 'late requests should all hit server2')
      puts "  summary: #{replies.size} requests, seamless failover from server1 to server2"
    end
  end
end
