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

# ZGuide Chapter 5 — Last Value Cache
# A caching proxy sits between publishers and subscribers. It caches
# the latest value for each topic. When a new subscriber joins, it
# immediately receives the cached value (snapshot) before live updates.
# Uses REQ/REP for snapshot requests and PUSH/PULL for forwarding.

describe 'Last Value Cache' do
  it 'serves cached values to late-joining subscribers' do
    pub_ep      = 'inproc://zg06_pub'
    sub_ep      = 'inproc://zg06_sub'
    snapshot_ep = 'inproc://zg06_snapshot'
    received_late = []

    cache = {}

    Async do |task|
      pull = OMQ::PULL.bind(pub_ep)
      pub  = OMQ::PUB.bind(sub_ep)
      pull.recv_timeout = 2

      forward_task = task.async do
        loop do
          msg = pull.receive.first
          topic, value = msg.split(' ', 2)
          cache[topic] = value
          pub << msg
        rescue IO::TimeoutError
          break
        end
      end

      snap = OMQ::REP.bind(snapshot_ep)
      snap.recv_timeout = 3

      snapshot_task = task.async do
        loop do
          snap.receive
          cached = cache.dup
          snap << cached.map { |k, v| "#{k} #{v}" }.join("\n")
          puts "  cache: snapshot served (#{cached.size} entries)"
        rescue IO::TimeoutError
          break
        end
      end

      # Publisher: sends weather data
      push = OMQ::PUSH.connect(pub_ep)
      5.times do |i|
        push << "weather.nyc #{70 + i}F"
        push << "weather.sfo #{60 + i}F"
        sleep 0.01
      end

      # Wait for all messages to be cached
      sleep 0.1

      # Late joiner: requests snapshot
      req = OMQ::REQ.connect(snapshot_ep)
      req.recv_timeout = 2
      req << 'SNAPSHOT'
      result = req.receive.first
      result.split("\n").each do |line|
        received_late << line
        puts "  late joiner (snapshot): #{line}"
      end
      req.close

      forward_task.wait
      snapshot_task.wait

      refute_empty received_late, 'late joiner should receive cached values'
      assert(received_late.any? { |m| m.include?('weather.nyc') }, 'should have NYC data')
      assert(received_late.any? { |m| m.include?('weather.sfo') }, 'should have SFO data')
      puts "  summary: late joiner got #{received_late.size} cached entries"
    ensure
      pull&.close
      pub&.close
      snap&.close
      push&.close
    end
  end
end
