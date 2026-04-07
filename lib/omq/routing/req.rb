# frozen_string_literal: true

module OMQ
  module Routing
    # REQ socket routing: round-robin send with strict send/recv alternation.
    #
    # REQ prepends an empty delimiter frame on send and strips it on receive.
    #
    class Req
      include RoundRobin
      include FairRecv

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine          = engine
        @recv_queue      = FairQueue.new
        @tasks           = []
        @state           = :ready        # :ready or :waiting_reply
        init_round_robin(engine)
      end


      # @return [FairQueue]
      #
      attr_reader :recv_queue


      # @param connection [Connection]
      #
      def connection_added(connection)
        add_fair_recv_connection(connection) do |msg|
          @state = :ready
          msg.first&.empty? ? msg[1..] : msg
        end
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
        raise SocketError, "REQ socket expects send/recv/send/recv order" unless @state == :ready
        @state = :waiting_reply
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

      private

      # REQ prepends empty delimiter frame on the wire.
      #
      def transform_send(parts) = [EMPTY_BINARY, *parts]
    end
  end
end
