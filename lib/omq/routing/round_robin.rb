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
      #   and no pump fiber is mid-write with a dequeued batch.
      #
      def send_queues_drained?
        @send_queue.empty? && @in_flight == 0
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
        @in_flight       = 0   # messages dequeued but not yet written
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
        @conn_send_tasks.delete(conn)
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
      # queue, writes to its peer, and yields. On disconnect, the
      # in-flight batch is dropped and the engine reconnect kicks in.
      #
      # Each batch is capped at BATCH_MSG_CAP messages OR BATCH_BYTE_CAP
      # bytes, whichever hits first. The cap exists for fairness when
      # multiple peers share the queue: without it, the first pump that
      # wakes up drains the entire queue in one non-blocking burst
      # before any other pump runs (TCP send buffers absorb bursts
      # without forcing a fiber yield). 512 KB lets large-message
      # workloads batch naturally (8 × 64 KB per batch) while keeping
      # per-pump latency bounded enough that small-message multi-peer
      # fairness still benefits.
      #
      # A `Task.yield` between batches ensures peer pumps actually
      # get a turn: `write_batch` may complete without yielding when
      # TCP buffers absorb the whole batch, so without this the first
      # pump to wake can drain a pre-filled queue in one continuous
      # run. The yield is effectively free when the scheduler has no
      # other work.
      #
      # @param conn [Connection]
      #
      def start_conn_send_pump(conn)
        task = @engine.spawn_conn_pump_task(conn, annotation: "send pump") do
          loop do
            batch = [@send_queue.dequeue]
            drain_send_queue_capped(batch)
            @in_flight += batch.size
            begin
              write_batch(conn, batch)
            ensure
              @in_flight -= batch.size
            end
            batch.each { |parts| @engine.emit_verbose_msg_sent(conn, parts) }
            Async::Task.current.yield
          end
        end
        @conn_send_tasks[conn] = task
        @tasks << task
      end


      BATCH_MSG_CAP  = 256
      BATCH_BYTE_CAP = 512 * 1024

      def drain_send_queue_capped(batch)
        bytes = batch_bytes(batch[0])
        while batch.size < BATCH_MSG_CAP && bytes < BATCH_BYTE_CAP
          msg = @send_queue.dequeue(timeout: 0)
          break unless msg
          batch << msg
          bytes += batch_bytes(msg)
        end
      end


      # Byte accounting for send-queue batching. Connection wrappers
      # (e.g. OMQ::Ractor's MarshalConnection) may enqueue non-string
      # parts that get transformed at write time — skip those for the
      # fairness cap rather than crashing on #bytesize.
      #
      def batch_bytes(parts)
        parts.sum { |p| p.respond_to?(:bytesize) ? p.bytesize : 0 }
      end


      def write_batch(conn, batch)
        if batch.size == 1
          conn.send_message(transform_send(batch[0]))
        else
          conn.write_messages(batch)
          conn.flush
        end
      end
    end
  end
end
