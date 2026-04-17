# frozen_string_literal: true

module OMQ
  module Routing
    # SCATTER socket routing: round-robin send to GATHER peers.
    #
    class Scatter
      include RoundRobin

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine = engine
        @tasks  = []
        init_round_robin(engine)
      end


      # SCATTER is write-only.
      #
      def recv_queue
        raise "SCATTER sockets cannot receive"
      end


      def dequeue_recv
        raise "SCATTER sockets cannot receive"
      end


      # No-op; SCATTER has no recv queue to unblock.
      #
      def unblock_recv
      end


      # @param connection [Connection]
      #
      def connection_added(connection)
        @connections << connection
        add_round_robin_send_connection(connection)
        start_reaper(connection)
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


      # Stops all background tasks (send pumps, reapers).
      #
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end

      private

      # Detects peer disconnection on write-only sockets by
      # blocking on a receive that only returns on disconnect.
      #
      # @param conn [Connection]
      #
      def start_reaper(conn)
        return if conn.is_a?(Transport::Inproc::DirectPipe)
        @tasks << @engine.spawn_conn_pump_task(conn, annotation: "reaper") do
          conn.receive_message # blocks until peer disconnects; then exits
        end
      end
    end
  end
end
