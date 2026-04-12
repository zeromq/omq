# frozen_string_literal: true

module OMQ
  module Routing
    # DEALER socket routing: round-robin send, fair-queue receive.
    #
    # No envelope manipulation — messages pass through unchanged.
    #
    class Dealer
      include RoundRobin
      include FairRecv


      # @param engine [Engine]
      #
      def initialize(engine)
        @engine     = engine
        @recv_queue = FairQueue.new
        @tasks      = []
        init_round_robin(engine)
      end


      # @return [FairQueue]
      #
      attr_reader :recv_queue


      # @param connection [Connection]
      #
      def connection_added(connection)
        add_fair_recv_connection(connection)
        add_round_robin_send_connection(connection)
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        @connections.delete(connection)
        @recv_queue.remove_queue(connection)
        remove_round_robin_send_connection(connection)
      end


      # @param parts [Array<String>]
      #
      def enqueue(parts)
        enqueue_round_robin(parts)
      end


      # Stops all background tasks.
      #
      # @return [void]
      #
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end
    end
  end
end
