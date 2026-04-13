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
      include FairRecv

      EMPTY_FRAME = "".b.freeze


      # @return [FairQueue]
      #
      attr_reader :recv_queue


      # @param engine [Engine]
      #
      def initialize(engine)
        @engine          = engine
        @recv_queue      = FairQueue.new
        @pending_replies = []
        @conn_queues     = {}  # connection => per-connection send queue
        @conn_send_tasks = {}  # connection => send pump task
        @tasks           = []
      end


      # @param connection [Connection]
      #
      def connection_added(connection)
        add_fair_recv_connection(connection) do |msg|
          delimiter = msg.index { |p| p.empty? } || msg.size
          envelope  = msg[0, delimiter]
          body      = msg[(delimiter + 1)..] || []

          @pending_replies << { conn: connection, envelope: envelope }
          body
        end

        q = Routing.build_queue(@engine.options.send_hwm, :block)
        @conn_queues[connection] = q
        @conn_send_tasks[connection] = ConnSendPump.start(@engine, connection, q, @tasks)
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        @pending_replies.reject! { |r| r[:conn] == connection }
        @recv_queue.remove_queue(connection)
        @conn_queues.delete(connection)
        @conn_send_tasks.delete(connection)&.stop
      end


      # Enqueues a reply. Routes to the connection that sent the matching
      # request by consuming the next pending_reply entry.
      #
      # @param parts [Array<String>]
      #
      def enqueue(parts)
        reply_info = @pending_replies.shift
        return unless reply_info
        conn = reply_info[:conn]
        @conn_queues[conn]&.enqueue([*reply_info[:envelope], EMPTY_FRAME, *parts])
      end


      # Stops all background tasks.
      #
      # @return [void]
      #
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end


      # @return [Boolean] true when all per-connection send queues are empty
      #
      def send_queues_drained?
        @conn_queues.values.all?(&:empty?)
      end

    end
  end
end
