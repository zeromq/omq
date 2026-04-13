# frozen_string_literal: true

module OMQ
  module Routing
    # PULL socket routing: fair-queue receive from PUSH peers.
    #
    class Pull
      include FairRecv


      # @param engine [Engine]
      #
      def initialize(engine)
        @engine     = engine
        @recv_queue = FairQueue.new
        @tasks      = []
      end


      # @return [FairQueue]
      #
      attr_reader :recv_queue


      # @param connection [Connection]
      #
      def connection_added(connection)
        add_fair_recv_connection(connection)
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        @recv_queue.remove_queue(connection)
        # recv pump stops on EOFError
      end


      # PULL is read-only.
      #
      def enqueue(_parts)
        raise "PULL sockets cannot send"
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
