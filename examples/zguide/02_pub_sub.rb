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

# ZGuide Chapter 2 — Publish-Subscribe
# Topic filtering, fan-out to multiple subscribers, and an XPUB/XSUB
# forwarding proxy. Demonstrates fire-and-forget data distribution
# with prefix-based topic filtering.

describe 'Publish-Subscribe' do
  it 'filters messages by topic prefix' do
    endpoint = 'inproc://zg02_filter'
    received_nyc = []
    received_sfo = []

    Async do |task|
      pub = OMQ::PUB.bind(endpoint)
      nyc_sub = OMQ::SUB.connect(endpoint, prefix: 'weather.nyc')
      sfo_sub = OMQ::SUB.connect(endpoint, prefix: 'weather.sfo')
      nyc_sub.recv_timeout = 1
      sfo_sub.recv_timeout = 1

      nyc_task = task.async do
        loop do
          msg = nyc_sub.receive.first
          received_nyc << msg
          puts "  nyc: #{msg}"
        rescue IO::TimeoutError
          break
        end
      end

      sfo_task = task.async do
        loop do
          msg = sfo_sub.receive.first
          received_sfo << msg
          puts "  sfo: #{msg}"
        rescue IO::TimeoutError
          break
        end
      end

      # Give subscriptions time to propagate
      sleep 0.01

      10.times do |i|
        pub << "weather.nyc #{60 + i}F"
        pub << "weather.sfo #{50 + i}F"
        pub << "sports.nba score-#{i}"
      end

      nyc_task.wait
      sfo_task.wait

      assert(received_nyc.all? { |m| m.start_with?('weather.nyc') })
      assert(received_sfo.all? { |m| m.start_with?('weather.sfo') })
      refute_empty received_nyc
      refute_empty received_sfo
      puts "  summary: nyc=#{received_nyc.size}, sfo=#{received_sfo.size}"
    ensure
      pub&.close
      nyc_sub&.close
      sfo_sub&.close
    end
  end


  it 'forwards messages through an XPUB/XSUB proxy' do
    upstream_ep   = 'inproc://zg02_upstream'
    downstream_ep = 'inproc://zg02_downstream'
    received = []

    Async do |task|
      # Proxy: XSUB (upstream) <-> XPUB (downstream)
      xsub = OMQ::XSUB.bind(upstream_ep)
      xpub = OMQ::XPUB.bind(downstream_ep)
      xsub.recv_timeout = 1
      xpub.recv_timeout = 0.1

      proxy = task.async do
        loop do
          begin
            event = xpub.receive.first
            xsub << event
          rescue IO::TimeoutError
            # no new subscriptions
          end

          begin
            msg = xsub.receive
            xpub << msg
          rescue IO::TimeoutError
            break
          end
        end
      end

      sub = OMQ::SUB.connect(downstream_ep, prefix: 'data')
      sub.recv_timeout = 1

      subscriber = task.async do
        loop do
          msg = sub.receive.first
          received << msg
          puts "  subscriber: #{msg}"
        rescue IO::TimeoutError
          break
        end
      end

      sleep 0.02

      pub = OMQ::PUB.connect(upstream_ep)
      sleep 0.02 # let subscription propagate
      5.times { |i| pub << "data.#{i}" }
      sleep 0.05 # let messages flow through proxy

      proxy.wait
      subscriber.wait

      refute_empty received, 'expected subscriber to receive messages through proxy'
      assert(received.all? { |m| m.start_with?('data') })
      puts "  summary: #{received.size} messages forwarded through proxy"
    ensure
      xsub&.close
      xpub&.close
      sub&.close
      pub&.close
    end
  end
end
