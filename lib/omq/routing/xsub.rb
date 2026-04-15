# frozen_string_literal: true

module OMQ
  module Routing
    # XSUB socket routing: like SUB but subscriptions sent as data messages.
    #
    # Subscriptions are sent as data frames: \x01 + prefix for subscribe,
    # \x00 + prefix for unsubscribe. Each connected PUB gets its own send
    # queue so subscription commands are delivered independently per peer.
    #
    class XSub

      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue


      # @param engine [Engine]
      #
      def initialize(engine)
        @engine          = engine
        @connections     = Set.new
        @recv_queue      = Routing.build_queue(engine.options.recv_hwm, :block)
        @conn_queues     = {}  # connection => per-connection send queue
        @conn_send_tasks = {}  # connection => send pump task
        @tasks           = []
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
        @connections << connection

        task = @engine.start_recv_pump(connection, @recv_queue)
        @tasks << task if task

        q = Routing.build_queue(@engine.options.send_hwm, :block)
        @conn_queues[connection] = q
        start_conn_send_pump(connection, q)
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        @connections.delete(connection)
        @conn_queues.delete(connection)
        @conn_send_tasks.delete(connection)&.stop
      end


      # Enqueues a subscription command (fan-out to all connected PUBs).
      #
      # @param parts [Array<String>]
      #
      def enqueue(parts)
        @connections.each do |conn|
          @conn_queues[conn]&.enqueue(parts)
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


      # @return [Boolean] true when all per-connection send queues are empty
      #
      def send_queues_drained?
        @conn_queues.values.all?(&:empty?)
      end


      private


      def start_conn_send_pump(conn, q)
        task = @engine.spawn_conn_pump_task(conn, annotation: "send pump") do
          loop do
            parts = q.dequeue
            frame = parts.first&.b

            next if frame.nil? || frame.empty?

            flag   = frame.getbyte(0)
            prefix = frame.byteslice(1..) || "".b

            case flag
            when 0x01
              conn.send_command(Protocol::ZMTP::Codec::Command.subscribe(prefix))
            when 0x00
              conn.send_command(Protocol::ZMTP::Codec::Command.cancel(prefix))
            end
          end
        end

        @conn_send_tasks[conn] = task
        @tasks << task
      end

    end
  end
end
