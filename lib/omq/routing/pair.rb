# frozen_string_literal: true

module OMQ
  module Routing
    # PAIR socket routing: exclusive 1-to-1 bidirectional.
    #
    # Only one peer connection is allowed. Send and recv queues are
    # created per-connection (and destroyed on disconnection) so
    # HWM is consistent with multi-peer socket types.
    #
    class Pair
      include FairRecv

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine         = engine
        @connection     = nil
        @recv_queue     = FairQueue.new
        @send_queue     = nil   # created per-connection
        @staging_queue  = StagingQueue.new(@engine.options.send_hwm)
        @send_pump      = nil
        @tasks          = []
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
          @send_queue = Routing.build_queue(@engine.options.send_hwm, :block)
          while (msg = @staging_queue.dequeue)
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
          @recv_queue.remove_queue(connection)
          if @send_queue
            while (msg = @send_queue.dequeue(timeout: 0))
              @staging_queue.prepend(msg)
            end
            @send_queue = nil
          end
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


      # Stops all background tasks.
      #
      # @return [void]
      #
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end


      # @return [Boolean] true when the staging and send queues are empty
      #
      def send_queues_drained?
        @staging_queue.empty? && (@send_queue.nil? || @send_queue.empty?)
      end

      private

      def start_send_pump(conn)
        @send_pump = @engine.spawn_pump_task(annotation: "send pump") do
          loop do
            batch = [@send_queue.dequeue]
            Routing.drain_send_queue(@send_queue, batch)
            begin
              batch.each { |parts| conn.write_message(parts) }
              conn.flush
              batch.each { |parts| @engine.emit_verbose_monitor_event(:message_sent, parts: parts) }
            rescue Protocol::ZMTP::Error, *CONNECTION_LOST
              batch.each { |parts| @staging_queue.prepend(parts) }
              @engine.connection_lost(conn)
              break
            end
          end
        end
        @tasks << @send_pump
      end
    end
  end
end
