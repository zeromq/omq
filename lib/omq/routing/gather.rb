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
        @recv_queue = Async::LimitedQueue.new(engine.options.recv_hwm)
        @tasks      = []
      end

      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue

      # @param connection [Connection]
      #
      def connection_added(connection)
        task = @engine.start_recv_pump(connection, @recv_queue)
        @tasks << task if task
      end

      # @param connection [Connection]
      #
      def connection_removed(connection)
        # recv pump stops on CONNECTION_LOST
      end

      # GATHER is read-only.
      #
      def enqueue(_parts)
        raise "GATHER sockets cannot send"
      end

      #
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end
    end
  end
end
