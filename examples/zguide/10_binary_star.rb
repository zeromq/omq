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

# ZGuide Chapter 4 — Binary Star Pattern
# Active/passive high-availability pair. The primary server handles
# client requests while exchanging heartbeats with a backup. When the
# primary fails, the backup detects the loss via heartbeat timeout and
# takes over. The client retries against the backup on timeout.
#
# Fencing rule: backup only takes over if heartbeats are lost (proving
# the primary is truly gone, not just a network partition between them).

describe 'Binary Star' do
  it 'backup takes over when primary fails' do
    primary_ep = 'inproc://zg10_primary'
    backup_ep  = 'inproc://zg10_backup'
    hb_ep      = 'inproc://zg10_heartbeat'
    served_by  = []

    Async do |task|
      hb_pub = OMQ::PUB.bind(hb_ep)

      hb_task = task.async do
        loop do
          hb_pub << 'HB'
          sleep 0.05
        end
      end

      primary_rep = OMQ::REP.bind(primary_ep)
      primary_rep.recv_timeout = 2

      primary_task = task.async do
        loop do
          msg = primary_rep.receive.first
          primary_rep << "primary:#{msg}"
          puts "  primary: served #{msg}"
        rescue IO::TimeoutError
          break
        end
      end

      backup_rep = OMQ::REP.bind(backup_ep)
      backup_rep.recv_timeout = 2

      backup_sub = OMQ::SUB.connect(hb_ep, prefix: 'HB')
      backup_sub.recv_timeout = 0.3

      backup_task = task.async do
        # Monitor heartbeats from primary
        loop do
          backup_sub.receive
        rescue IO::TimeoutError
          puts "  backup: primary heartbeat lost — taking over!"
          break
        end

        # Take over serving
        loop do
          msg = backup_rep.receive.first
          backup_rep << "backup:#{msg}"
          puts "  backup: served #{msg}"
        rescue IO::TimeoutError
          break
        end
      end

      sleep 0.02

      send_request = lambda do |body|
        req = OMQ::REQ.connect(primary_ep)
        req.recv_timeout = 0.2
        req << body
        begin
          reply = req.receive.first
          req.close
          reply
        rescue IO::TimeoutError
          req.close
          req = OMQ::REQ.connect(backup_ep)
          req.recv_timeout = 1
          req << body
          reply = req.receive.first
          req.close
          reply
        end
      end

      served_by << send_request.call('req-1')
      served_by << send_request.call('req-2')

      puts "  --- primary crashes ---"
      hb_task.stop
      primary_task.stop

      sleep 0.5

      served_by << send_request.call('req-3')
      served_by << send_request.call('req-4')

      backup_task.stop

      puts "  responses: #{served_by.inspect}"
      assert_equal 'primary:req-1', served_by[0]
      assert_equal 'primary:req-2', served_by[1]
      assert_equal 'backup:req-3', served_by[2]
      assert_equal 'backup:req-4', served_by[3]
    ensure
      hb_pub&.close
      primary_rep&.close
      backup_rep&.close
      backup_sub&.close
    end
  end
end
