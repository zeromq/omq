# frozen_string_literal: true

module OMQ
  module Routing
    # PAIR socket routing: exclusive 1-to-1 bidirectional.
    #
    # Only one peer connection is allowed. Messages flow through
    # internal send/recv queues backed by Async::LimitedQueue.
    #
    class Pair

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine     = engine
        @connection = nil
        @recv_queue = Async::LimitedQueue.new(engine.options.recv_hwm)
        @send_queue = Async::LimitedQueue.new(engine.options.send_hwm)
        @tasks          = []
        @send_pump_idle = true
      end

      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue, :send_queue

      # @param connection [Connection]
      # @raise [RuntimeError] if a connection already exists
      #
      def connection_added(connection)
        raise "PAIR allows only one peer" if @connection
        @connection = connection
        task = @engine.start_recv_pump(connection, @recv_queue)
        @tasks << task if task
        start_send_pump(connection) unless connection.is_a?(Transport::Inproc::DirectPipe)
      end

      # @param connection [Connection]
      #
      def connection_removed(connection)
        if @connection == connection
          @connection = nil
          @send_pump&.stop
          @send_pump = nil
        end
      end

      # @param parts [Array<String>]
      #
      def enqueue(parts)
        conn = @connection
        if conn.is_a?(Transport::Inproc::DirectPipe) && conn.direct_recv_queue
          conn.send_message(parts)
        else
          @send_queue.enqueue(parts)
        end
      end

      #
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end

      def send_pump_idle? = @send_pump_idle

      private

      def start_send_pump(conn)
        @send_pump = @engine.spawn_pump_task(annotation: "send pump") do
          loop do
            @send_pump_idle = true
            batch = [@send_queue.dequeue]
            @send_pump_idle = false
            Routing.drain_send_queue(@send_queue, batch)
            batch.each { |parts| conn.write_message(parts) }
            conn.flush
          end
        rescue *CONNECTION_LOST
          @engine.connection_lost(conn)
        end
        @tasks << @send_pump
      end
    end
  end
end
