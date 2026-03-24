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

# ZGuide Chapter 5 — Clone Pattern (simplified)
# Reliable state synchronization: a server maintains a key-value store,
# publishes updates via PUB, and serves snapshots via REQ/REP.
# Clients get a snapshot first, then apply live updates ordered by
# sequence number. Demonstrates the core Clone technique.

describe 'Clone' do
  it 'synchronizes state via snapshot + live updates' do
    pub_ep      = 'inproc://zg07_pub'
    snapshot_ep = 'inproc://zg07_snap'

    store = {}
    seq = 0

    client_store = {}

    Async do |task|
      pub  = OMQ::PUB.bind(pub_ep)
      snap = OMQ::REP.bind(snapshot_ep)
      snap.recv_timeout = 0.2

      server = task.async do
        sleep 0.02

        # Publish some initial updates
        5.times do |i|
          seq += 1
          key = "key-#{i}"
          val = "val-#{i}"
          store[key] = { value: val, seq: seq }
          pub << "#{seq}|#{key}|#{val}"
          puts "  server: published #{key}=#{val} (seq=#{seq})"
          sleep 0.01
        end

        # Serve snapshot requests
        3.times do
          begin
            msg = snap.receive.first
            if msg == 'SNAPSHOT'
              snapshot_data = store.map { |k, v| "#{v[:seq]}|#{k}|#{v[:value]}" }.join("\n")
              snap << snapshot_data
              puts "  server: snapshot served (#{store.size} entries, up to seq=#{seq})"
            end
          rescue IO::TimeoutError
            # no request
          end
        end

        sleep 0.05

        # Publish more updates after snapshot
        3.times do |i|
          seq += 1
          key = "key-#{i}"
          val = "updated-#{i}"
          store[key] = { value: val, seq: seq }
          pub << "#{seq}|#{key}|#{val}"
          puts "  server: published #{key}=#{val} (seq=#{seq})"
          sleep 0.01
        end
      end

      sleep 0.05

      # Client: subscribe first, snapshot second, apply buffered updates
      sub = OMQ::SUB.connect(pub_ep)
      sub.recv_timeout = 1.5

      # Buffer live updates in an Async task while fetching snapshot
      buffered = []
      buffer_task = task.async do
        loop do
          msg = sub.receive.first
          buffered << msg
        rescue IO::TimeoutError
          break
        end
      end

      sleep 0.05

      # Get snapshot
      req = OMQ::REQ.connect(snapshot_ep)
      req.recv_timeout = 1
      req << 'SNAPSHOT'
      snapshot = req.receive.first
      req.close

      snapshot_seq = 0
      snapshot.split("\n").each do |line|
        s, k, v = line.split('|', 3)
        s = s.to_i
        client_store[k] = v
        snapshot_seq = s if s > snapshot_seq
        puts "  client (snapshot): #{k}=#{v} seq=#{s}"
      end

      buffer_task.wait

      # Apply buffered updates with seq > snapshot_seq
      buffered.each do |line|
        s, k, v = line.split('|', 3)
        s = s.to_i
        if s > snapshot_seq
          client_store[k] = v
          puts "  client (live): #{k}=#{v} seq=#{s}"
        else
          puts "  client (skip): #{k}=#{v} seq=#{s} (already in snapshot)"
        end
      end

      server.wait

      refute_empty client_store, 'client should have state'
      puts "  client store: #{client_store.inspect}"

      assert_equal 'updated-0', client_store['key-0'], 'should have live update for key-0'
      assert client_store.key?('key-3'), 'should have snapshot data for key-3'
    ensure
      pub&.close
      snap&.close
      sub&.close
    end
  end
end
