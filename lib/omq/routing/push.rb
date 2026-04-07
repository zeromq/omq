# frozen_string_literal: true

module OMQ
  module Routing
    # PUSH socket routing: round-robin send to PULL peers.
    #
    class Push
      include RoundRobin

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine = engine
        @tasks  = []
        init_round_robin(engine)
      end


      # PUSH is write-only.
      #
      def recv_queue
        raise "PUSH sockets cannot receive"
      end


      # @param connection [Connection]
      #
      def connection_added(connection)
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


      # Detects peer disconnection on write-only sockets. Without
      # this, a dead peer is only noticed on the next send — which
      # may succeed if the kernel send buffer absorbs the data.
      #
      def start_reaper(conn)
        return if conn.is_a?(Transport::Inproc::DirectPipe)
        @tasks << @engine.spawn_pump_task(annotation: "reaper") do
          conn.receive_message # blocks until peer disconnects
        rescue *CONNECTION_LOST
          @engine.connection_lost(conn)
        end
      end
    end
  end
end
