# frozen_string_literal: true

module OMQ
  module Routing
    # REQ socket routing: round-robin send with strict send/recv alternation.
    #
    # REQ prepends an empty delimiter frame on send and strips it on receive.
    #
    class Req
      include RoundRobin

      # Shared frozen empty binary string to avoid repeated allocations.
      EMPTY_BINARY = ::Protocol::ZMTP::Codec::EMPTY_BINARY


      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue


      # @param engine [Engine]
      #
      def initialize(engine)
        @engine     = engine
        @recv_queue = Routing.build_queue(engine.options.recv_hwm, :block)
        @state      = :ready        # :ready or :waiting_reply
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
        @engine.start_recv_pump(connection, @recv_queue) do |msg|
          @state = :ready
          msg.first&.empty? ? msg[1..] : msg
        end

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
        raise SocketError, "REQ socket expects send/recv/send/recv order" unless @state == :ready
        @state = :waiting_reply
        enqueue_round_robin(parts)
      end


      private


      # REQ prepends empty delimiter frame on the wire.
      #
      def transform_send(parts)
        parts.dup.unshift(EMPTY_BINARY)
      end

    end
  end
end
