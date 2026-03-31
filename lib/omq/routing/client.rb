# frozen_string_literal: true

module OMQ
  module Routing
    # CLIENT socket routing: round-robin send, fair-queue receive.
    #
    # Same as DEALER — no envelope manipulation.
    #
    class Client
      include RoundRobin

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine     = engine
        @recv_queue = Async::LimitedQueue.new(engine.options.recv_hwm)
        @tasks      = []
        init_round_robin(engine)
      end

      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue, :send_queue

      # @param connection [Connection]
      #
      def connection_added(connection)
        @connections << connection
        signal_connection_available
        task = @engine.start_recv_pump(connection, @recv_queue)
        @tasks << task if task
        start_send_pump unless @send_pump_started
      end

      # @param connection [Connection]
      #
      def connection_removed(connection)
        @connections.delete(connection)
      end

      # @param parts [Array<String>]
      #
      def enqueue(parts)
        @send_queue.enqueue(parts)
      end

      #
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end
    end
  end
end
