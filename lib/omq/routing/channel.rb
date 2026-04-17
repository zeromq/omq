# frozen_string_literal: true

module OMQ
  module Routing
    # CHANNEL socket routing: exclusive 1-to-1 bidirectional.
    #
    class Channel
      # @param engine [Engine]
      #
      def initialize(engine)
        @engine         = engine
        @connection     = nil
        @recv_queue     = Routing.build_queue(engine.options.recv_hwm, :block)
        @send_queue     = nil
        @staging_queue  = Routing.build_queue(engine.options.send_hwm, :block)
        @send_pump      = nil
        @tasks          = []
      end


      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue


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
      # @raise [RuntimeError] if a connection already exists
      #
      def connection_added(connection)
        raise "CHANNEL allows only one peer" if @connection
        @connection = connection

        task = @engine.start_recv_pump(connection, @recv_queue)
        @tasks << task if task

        unless connection.is_a?(Transport::Inproc::DirectPipe)
          @send_queue = Routing.build_queue(@engine.options.send_hwm, :block)
          while (msg = @staging_queue.dequeue(timeout: 0))
            @send_queue.enqueue(msg)
          end
          start_send_pump(connection)
        end
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        if @connection == connection
          @connection = nil
          @send_queue = nil
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
        elsif @send_queue
          @send_queue.enqueue(parts)
        else
          @staging_queue.enqueue(parts)
        end
      end


      # Stops all background tasks (send pumps).
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end


      # True when the staging and send queues are empty.
      #
      def send_queues_drained?
        @staging_queue.empty? && (@send_queue.nil? || @send_queue.empty?)
      end

      private

      def start_send_pump(conn)
        @send_pump = @engine.spawn_pump_task(annotation: "send pump") do
          batch = []

          loop do
            Routing.dequeue_batch(@send_queue, batch)
            begin
              batch.each { |parts| conn.write_message(parts) }
              conn.flush
            rescue Protocol::ZMTP::Error, *CONNECTION_LOST
              @engine.connection_lost(conn)
              break
            end
            batch.clear
          end
        end
        @tasks << @send_pump
      end
    end
  end
end
