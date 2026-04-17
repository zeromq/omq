# frozen_string_literal: true

module OMQ
  module Routing
    # CLIENT socket routing: round-robin send, fair-queue receive.
    #
    # Same as DEALER — no envelope manipulation.
    #
    class Client
      include RoundRobin


      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue


      # @param engine [Engine]
      #
      def initialize(engine)
        @engine     = engine
        @recv_queue = Routing.build_queue(engine.options.recv_hwm, :block)
        init_round_robin(engine)
      end


      # Dequeues the next received message. Blocks until one is available.
      #
      # @return [Array<String>, nil]
      #
      def dequeue_recv
        @recv_queue.dequeue
      end


      # Wakes a blocked {#dequeue_recv} with a nil sentinel.
      #
      # @return [void]
      #
      def unblock_recv
        @recv_queue.enqueue(nil)
      end


      # @param connection [Connection]
      #
      def connection_added(connection)
        @connections << connection
        @engine.start_recv_pump(connection, @recv_queue)
        add_round_robin_send_connection(connection)
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        @connections.delete(connection)
        remove_round_robin_send_connection(connection)
      end


      # @param parts [Array<String>]
      #
      def enqueue(parts)
        enqueue_round_robin(parts)
      end

    end
  end
end
