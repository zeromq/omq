# frozen_string_literal: true

module OMQ
  module ZMTP
    module Routing
      # PAIR socket routing: exclusive 1-to-1 bidirectional.
      #
      # Only one peer connection is allowed. Messages flow through
      # internal send/recv queues backed by Async::LimitedQueue.
      #
      class Pair

        # @param engine [Engine]
        #
        def initialize(engine)
          @engine     = engine
          @connection = nil
          @recv_queue = Async::LimitedQueue.new(engine.options.recv_hwm)
          @send_queue = Async::LimitedQueue.new(engine.options.send_hwm)
          @tasks      = []
        end

        # @return [Async::LimitedQueue]
        #
        attr_reader :recv_queue, :send_queue

        # @param connection [Connection]
        # @raise [RuntimeError] if a connection already exists
        #
        def connection_added(connection)
          raise "PAIR allows only one peer" if @connection
          @connection = connection
          task = @engine.start_recv_pump(connection, @recv_queue)
          @tasks << task if task
          start_send_pump(connection)
        end

        # @param connection [Connection]
        #
        def connection_removed(connection)
          @connection = nil if @connection == connection
        end

        # @param parts [Array<String>]
        #
        def enqueue(parts)
          @send_queue.enqueue(parts)
        end

        #
        def stop
          @tasks.each(&:stop)
          @tasks.clear
        end

        private

        def start_send_pump(conn)
          @tasks << Reactor.spawn_pump do
            loop { conn.send_message(@send_queue.dequeue) }
          rescue *ZMTP::CONNECTION_LOST
            @engine.connection_lost(conn)
          end
        end
      end
    end
  end
end
