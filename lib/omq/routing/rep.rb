# frozen_string_literal: true

module OMQ
  module Routing
    # REP socket routing: fair-queue receive, reply routed back to sender.
    #
    # REP strips the routing envelope (everything up to and including the
    # empty delimiter) on receive, saves it internally, and restores it
    # on send.
    #
    class Rep
      EMPTY_FRAME = "".b.freeze


      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue


      # @param engine [Engine]
      #
      def initialize(engine)
        @engine          = engine
        @recv_queue      = Routing.build_queue(engine.options.recv_hwm, :block)
        @pending_replies = []
        @conn_queues     = {}
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
          delimiter = msg.index { |p| p.empty? } || msg.size
          envelope  = msg[0, delimiter]
          body      = msg[(delimiter + 1)..] || []

          @pending_replies << [connection, envelope]
          body
        end

        q = Routing.build_queue(@engine.options.send_hwm, :block)
        @conn_queues[connection] = q
        ConnSendPump.start(@engine, connection, q)
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        @pending_replies.reject! { |r| r[0] == connection }
        @conn_queues.delete(connection)
      end


      # Enqueues a reply. Routes to the connection that sent the matching
      # request by consuming the next pending_reply entry.
      #
      # @param parts [Array<String>]
      #
      def enqueue(parts)
        reply_info = @pending_replies.shift
        return unless reply_info

        conn, envelope = reply_info
        msg = envelope
        msg << EMPTY_FRAME
        msg.concat(parts)
        @conn_queues[conn]&.enqueue(msg)
      end


      # @return [Boolean] true when all per-connection send queues are empty
      #
      def send_queues_drained?
        @conn_queues.values.all?(&:empty?)
      end

    end
  end
end
