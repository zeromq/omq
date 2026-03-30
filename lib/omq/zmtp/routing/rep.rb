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
          @send_pump_idle    = true
        end

        # @return [Async::LimitedQueue]
        #
        attr_reader :recv_queue, :send_queue

        # @param connection [Connection]
        #
        def connection_added(connection)
          task = @engine.start_recv_pump(connection, @recv_queue) do |msg|
            delimiter = msg.index(&:empty?) || msg.size
            envelope  = msg[0, delimiter]
            body      = msg[(delimiter + 1)..] || []
            @pending_replies << { conn: connection, envelope: envelope }
            body
          end
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

        def send_pump_idle? = @send_pump_idle


        def start_send_pump
          @send_pump_started = true
          @tasks << @engine.spawn_pump_task(annotation: "send pump") do
            loop do
              @send_pump_idle = true
              batch = [@send_queue.dequeue]
              @send_pump_idle = false
              Routing.drain_send_queue(@send_queue, batch)

              written = Set.new
              batch.each do |parts|
                reply_info = @pending_replies.shift
                next unless reply_info
                conn = reply_info[:conn]
                begin
                  conn.write_message([*reply_info[:envelope], "".b, *parts])
                  written << conn
                rescue *ZMTP::CONNECTION_LOST
                  # connection lost mid-write
                end
              end

              written.each do |conn|
                conn.flush
              rescue *ZMTP::CONNECTION_LOST
                # connection lost mid-flush
              end
            end
          end
        end
      end
    end
  end
end
