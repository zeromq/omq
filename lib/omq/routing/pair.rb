# frozen_string_literal: true

module OMQ
  module Routing
    # PAIR socket routing: exclusive 1-to-1 bidirectional.
    #
    # Only one peer connection is allowed at a time. The send queue
    # is socket-level (one shared bounded queue), and a single send
    # pump fiber drains it into the connected peer. On disconnect,
    # the in-flight batch is dropped (matching libzmq).
    #
    class Pair
      include FairRecv

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine     = engine
        @connection = nil
        @recv_queue = FairQueue.new
        @send_queue = Routing.build_queue(@engine.options.send_hwm, :block)
        @send_pump  = nil
        @tasks      = []
      end


      # @return [FairQueue]
      #
      attr_reader :recv_queue

      # @param connection [Connection]
      # @raise [RuntimeError] if a connection already exists
      #
      def connection_added(connection)
        raise "PAIR allows only one peer" if @connection
        @connection = connection

        add_fair_recv_connection(connection)

        unless connection.is_a?(Transport::Inproc::DirectPipe)
          start_send_pump(connection)
        end
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        if @connection == connection
          @connection = nil
          @recv_queue.remove_queue(connection)
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


      # Stops all background tasks.
      #
      # @return [void]
      #
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end


      # @return [Boolean] true when the shared send queue is empty
      #
      def send_queues_drained?
        @send_queue.empty?
      end

      private

      def start_send_pump(conn)
        @send_pump = @engine.spawn_pump_task(annotation: "send pump") do
          loop do
            batch = [@send_queue.dequeue]
            Routing.drain_send_queue(@send_queue, batch)
            if batch.size == 1
              conn.write_message(batch[0])
            else
              conn.write_messages(batch)
            end
            conn.flush
            batch.each { |parts| @engine.emit_verbose_monitor_event(:message_sent, parts: parts) }
          rescue Protocol::ZMTP::Error, *CONNECTION_LOST
            @engine.connection_lost(conn)
            break
          end
        end
        @tasks << @send_pump
      end
    end
  end
end
