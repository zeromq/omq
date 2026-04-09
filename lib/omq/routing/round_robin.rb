# frozen_string_literal: true

module OMQ
  module Routing
    # Mixin for routing strategies that load-balance via work-stealing.
    #
    # One shared bounded send queue per socket (`send_hwm` enforced
    # at the socket level, not per peer). Each connected peer gets its
    # own send pump fiber that races to drain the shared queue. Slow
    # peers' pumps naturally block on their own TCP flush; fast peers'
    # pumps keep dequeuing. The result is work-stealing load balancing,
    # which is strictly better than libzmq's strict per-pipe round-robin
    # for PUSH-style patterns.
    #
    # See DESIGN.md "Per-socket HWM (not per-connection)" for the
    # full reasoning.
    #
    # Including classes must call `init_round_robin(engine)` from
    # their #initialize.
    #
    module RoundRobin
      # @return [Boolean] true when the shared send queue is empty
      #
      def send_queues_drained?
        @send_queue.empty?
      end

      private

      # Initializes the shared send queue for the including class.
      #
      # @param engine [Engine]
      #
      def init_round_robin(engine)
        @connections     = []
        @send_queue      = Routing.build_queue(engine.options.send_hwm, :block)
        @direct_pipe     = nil
        @conn_send_tasks = {}  # conn => send pump task
      end


      # Registers a connection and starts its send pump.
      # Call from #connection_added.
      #
      # @param conn [Connection]
      #
      def add_round_robin_send_connection(conn)
        @connections << conn
        update_direct_pipe
        start_conn_send_pump(conn)
      end


      # Removes the connection and stops its send pump. Any message
      # the pump had already dequeued but not yet written is dropped --
      # matching libzmq's behavior on `pipe_terminated`. PUSH has no
      # cross-peer ordering guarantee, so this is safe.
      #
      # @param conn [Connection]
      #
      def remove_round_robin_send_connection(conn)
        update_direct_pipe
        @conn_send_tasks.delete(conn)&.stop
      end


      # Updates the direct-pipe shortcut for inproc single-peer bypass.
      #
      def update_direct_pipe
        if @connections.size == 1 && @connections.first.is_a?(Transport::Inproc::DirectPipe)
          @direct_pipe = @connections.first
        else
          @direct_pipe = nil
        end
      end


      # Enqueues a message. For inproc single-peer, bypasses the queue
      # and writes directly to the peer's recv queue. Otherwise blocks
      # on the shared bounded send queue (backpressure when full).
      #
      def enqueue_round_robin(parts)
        pipe = @direct_pipe
        if pipe&.direct_recv_queue
          pipe.send_message(transform_send(parts))
        else
          @send_queue.enqueue(parts)
        end
      end


      # Transforms parts before sending. Override in subclasses
      # (e.g. REQ prepends an empty delimiter frame).
      #
      # @param parts [Array<String>]
      # @return [Array<String>]
      #
      def transform_send(parts) = parts


      # Spawns a send pump for one connection. Drains the shared send
      # queue, batches up to BATCH_CAP messages per cycle, writes to its
      # peer, and yields. The cap is what enforces work-stealing fairness
      # across the N per-conn pumps -- without it, the first pump that
      # wakes up would drain the entire queue in one non-blocking burst
      # before any other pump got a turn (TCP send buffers absorb bursts
      # without forcing a fiber yield). On disconnect, the in-flight
      # batch is dropped and the engine reconnect kicks in.
      #
      # @param conn [Connection]
      #
      def start_conn_send_pump(conn)
        task = @engine.spawn_pump_task(annotation: "send pump") do
          loop do
            batch = [@send_queue.dequeue]
            drain_send_queue_capped(batch)
            write_batch(conn, batch)
            batch.each { |parts| @engine.emit_verbose_monitor_event(:message_sent, parts: parts) }
          rescue Protocol::ZMTP::Error, *CONNECTION_LOST
            @engine.connection_lost(conn)
            break
          end
        end
        @conn_send_tasks[conn] = task
        @tasks << task
      end


      # Per-cycle batch cap. Bounded by BATCH_CAP messages so other
      # per-conn pumps get a turn at the shared send queue.
      #
      BATCH_CAP = 64

      def drain_send_queue_capped(batch)
        while batch.size < BATCH_CAP
          msg = @send_queue.dequeue(timeout: 0)
          break unless msg
          batch << msg
        end
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
