# frozen_string_literal: true

module OMQ
  module Routing
    # Mixin for routing strategies that send via round-robin.
    #
    # Provides reactive connection management: Async::Promise waits
    # for the first connection, Array#cycle handles round-robin,
    # and a new Promise is created when all connections drop.
    #
    # Each connected peer gets its own bounded send queue and a
    # dedicated send pump fiber, ensuring HWM is enforced per peer.
    #
    # Including classes must call `init_round_robin(engine)` from
    # their #initialize.
    #
    module RoundRobin
      # @return [Boolean] true when the staging queue and all per-connection
      #   send queues are empty
      #
      def send_queues_drained?
        @staging_queue.empty? && @conn_queues.values.all?(&:empty?)
      end

      private

      # Initializes round-robin state for the including class.
      #
      # @param engine [Engine]
      #
      def init_round_robin(engine)
        @connections          = []
        @cycle                = @connections.cycle
        @connection_available = Async::Promise.new
        @conn_queues          = {}  # connection => send queue
        @conn_send_tasks      = {}  # connection => send pump task
        @direct_pipe          = nil
        @staging_queue        = Routing.build_queue(@engine.options.send_hwm, :block)
      end


      # Creates a per-connection send queue and starts its send pump.
      # Call from #connection_added after appending to @connections.
      #
      # @param conn [Connection]
      #
      def add_round_robin_send_connection(conn)
        update_direct_pipe
        q = Routing.build_queue(@engine.options.send_hwm, :block)
        @conn_queues[conn] = q
        start_conn_send_pump(conn, q)
        drain_staging_to(q)
        signal_connection_available
      end


      # Stops the per-connection send pump and removes the queue.
      # Call from #connection_removed.
      #
      # @param conn [Connection]
      #
      def remove_round_robin_send_connection(conn)
        update_direct_pipe
        @conn_queues.delete(conn)&.close
        @conn_send_tasks.delete(conn)&.stop
      end


      # Resolves the connection-available promise so blocked
      # senders can proceed.
      #
      def signal_connection_available
        unless @connection_available.resolved?
          @connection_available.resolve(true)
        end
      end


      # Updates the direct-pipe shortcut for inproc single-peer bypass.
      # Call from connection_added after @connections is updated.
      #
      def update_direct_pipe
        if @connections.size == 1 && @connections.first.is_a?(Transport::Inproc::DirectPipe)
          @direct_pipe = @connections.first
        else
          @direct_pipe = nil
        end
      end


      # Enqueues directly to the inproc peer's recv queue if possible.
      # When peers are connected, picks the next one round-robin and
      # enqueues into its per-connection send queue (blocking if full).
      # When no peers are connected yet, buffers in a staging queue
      # (bounded by send_hwm) — drained into the first peer's queue
      # when it connects.
      #
      def enqueue_round_robin(parts)
        pipe = @direct_pipe
        if pipe&.direct_recv_queue
          pipe.send_message(transform_send(parts))
        elsif @connections.empty?
          @staging_queue.enqueue(parts)
        else
          conn = next_connection
          @conn_queues[conn].enqueue(parts)
        end
      rescue Async::Queue::ClosedError
        retry
      end


      # Drains the staging queue into the given per-connection queue.
      # Called when the first peer connects, to deliver messages that
      # were enqueued before any connection existed.
      #
      def drain_staging_to(q)
        while (msg = @staging_queue.dequeue(timeout: 0))
          q.enqueue(msg)
        end
      end


      # Blocks until a connection is available, then returns
      # the next one in round-robin order.
      #
      # @return [Connection]
      #
      def next_connection
        @cycle.next
      rescue StopIteration
        @connection_available = Async::Promise.new
        @connection_available.wait
        @cycle = @connections.cycle
        retry
      end


      # Transforms parts before sending. Override in subclasses
      # (e.g. REQ prepends an empty delimiter frame).
      #
      # @param parts [Array<String>]
      # @return [Array<String>]
      #
      def transform_send(parts) = parts


      # Starts a dedicated send pump for one connection.
      # Batches messages for throughput; flushes after each batch.
      # Calls Engine#connection_lost on disconnect so reconnect fires.
      #
      # @param conn [Connection]
      # @param q [Async::LimitedQueue] the connection's send queue
      #
      def start_conn_send_pump(conn, q)
        task = @engine.spawn_pump_task(annotation: "send pump") do
          loop do
            batch = [q.dequeue]
            Routing.drain_send_queue(q, batch)
            write_batch(conn, batch)
          rescue Protocol::ZMTP::Error, *CONNECTION_LOST
            @engine.connection_lost(conn)
            break
          end
        end
        @conn_send_tasks[conn] = task
        @tasks << task
      end


      def write_batch(conn, batch)
        if batch.size == 1
          conn.send_message(transform_send(batch[0]))
        else
          batch.each { |parts| conn.write_message(transform_send(parts)) }
          conn.flush
        end
      end
    end
  end
end
