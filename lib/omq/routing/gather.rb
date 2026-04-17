# frozen_string_literal: true

module OMQ
  module Routing
    # GATHER socket routing: fair-queue receive from SCATTER peers.
    #
    class Gather
      # @param engine [Engine]
      #
      def initialize(engine)
        @engine     = engine
        @recv_queue = Routing.build_queue(engine.options.recv_hwm, :block)
        @tasks      = []
      end


      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue


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
        task = @engine.start_recv_pump(connection, @recv_queue)
        @tasks << task if task
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
      end


      # GATHER is read-only.
      #
      def enqueue(_parts)
        raise "GATHER sockets cannot send"
      end


      # Stops all background tasks.
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end
    end
  end
end
