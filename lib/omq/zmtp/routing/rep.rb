# frozen_string_literal: true

module OMQ
  module ZMTP
    module Routing
      # REP socket routing: fair-queue receive, reply routed back to sender.
      #
      # REP strips the routing envelope (everything up to and including the
      # empty delimiter) on receive, saves it internally, and restores it
      # on send.
      #
      class Rep
        # @param engine [Engine]
        #
        def initialize(engine)
          @engine            = engine
          @recv_queue        = Async::LimitedQueue.new(engine.options.recv_hwm)
          @send_queue        = Async::LimitedQueue.new(engine.options.send_hwm)
          @pending_replies   = []
          @tasks             = []
          @send_pump_started = false
        end

        # @return [Async::LimitedQueue]
        #
        attr_reader :recv_queue, :send_queue

        # @param connection [Connection]
        #
        def connection_added(connection)
          transform = ->(msg) {
            envelope = []
            while msg.first && !msg.first.empty?
              envelope << msg.shift
            end
            msg.shift # remove empty delimiter
            @pending_replies << { conn: connection, envelope: envelope }
            msg
          }
          task = @engine.start_recv_pump(connection, @recv_queue, transform: transform)
          @tasks << task if task
          start_send_pump unless @send_pump_started
        end

        # @param connection [Connection]
        #
        def connection_removed(connection)
          # Remove any pending replies for this connection
          @pending_replies.reject! { |r| r[:conn] == connection }
        end

        # Enqueues a reply for sending.
        #
        # @param parts [Array<String>]
        #
        def enqueue(parts)
          @send_queue.enqueue(parts)
        end

        def stop
          @tasks.each(&:stop)
          @tasks.clear
        end

        private

        def start_send_pump
          @send_pump_started = true
          @tasks << Reactor.spawn_pump do
            loop do
              parts = @send_queue.dequeue
              reply_info = @pending_replies.shift
              next unless reply_info
              reply_info[:conn].send_message([*reply_info[:envelope], "".b, *parts])
            end
          rescue EOFError
            # connection lost mid-write
          end
        end
      end
    end
  end
end
