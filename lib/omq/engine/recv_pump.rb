# frozen_string_literal: true

module OMQ
  class Engine
    # Recv pump for a connection.
    #
    # For inproc DirectPipe: wires the direct recv path (no fiber spawned).
    # For TCP/IPC: spawns a transient task that reads messages from the
    # connection and enqueues them into +recv_queue+.
    #
    # The two-method structure (with/without transform) is intentional for
    # YJIT: it gives the JIT a monomorphic call per routing strategy instead
    # of a megamorphic `transform.call` dispatch inside a shared loop.
    #
    class RecvPump
      # Max messages read from one connection before yielding to the
      # scheduler. Prevents a busy peer from starving its siblings in
      # fair-queue recv sockets.
      FAIRNESS_MESSAGES = 64


      # Max bytes read from one connection before yielding. Only counted
      # for ZMTP connections (inproc skips the check). Complements
      # {FAIRNESS_MESSAGES}: small-message floods are bounded by count,
      # large-message floods by bytes.
      FAIRNESS_BYTES    = 1 << 20 # 1 MB


      # Public entry point — callers use the class method.
      #
      # @param parent [Async::Task, Async::Barrier] parent to spawn under
      # @param conn [Connection, Transport::Inproc::DirectPipe]
      # @param recv_queue [SignalingQueue]
      # @param engine [Engine]
      # @param transform [Proc, nil]
      # @return [Async::Task, nil]
      #
      def self.start(parent, conn, recv_queue, engine, transform)
        new(conn, recv_queue, engine).start(parent, transform)
      end


      # @param conn [Connection, Transport::Inproc::DirectPipe]
      # @param recv_queue [Routing::SignalingQueue]
      # @param engine [Engine]
      #
      def initialize(conn, recv_queue, engine)
        @conn        = conn
        @recv_queue  = recv_queue
        @engine      = engine
        @count_bytes = conn.instance_of?(Protocol::ZMTP::Connection)
      end


      # Starts the recv pump. For inproc DirectPipe, wires the direct path
      # (no task spawned). For TCP/IPC, spawns a fiber that reads messages.
      #
      # @param parent_task [Async::Task]
      # @param transform [Proc, nil] optional per-message transform
      # @return [Async::Task, nil]
      #
      def start(parent_task, transform)
        if @conn.is_a?(Transport::Inproc::DirectPipe) && @conn.peer
          @conn.peer.direct_recv_queue     = @recv_queue
          @conn.peer.direct_recv_transform = transform
          return nil
        end

        if transform
          start_with_transform(parent_task, transform)
        else
          start_direct(parent_task)
        end
      end

      private


      # Recv loop with per-message transform (e.g. Marshal.load for
      # cross-Ractor transport). Kept separate from {#start_direct} so
      # YJIT sees a monomorphic transform.call site.
      #
      # @param parent [Async::Task, Async::Barrier]
      # @param transform [Proc]
      # @return [Async::Task]
      #
      def start_with_transform(parent, transform)
        conn, recv_queue, engine, count_bytes = @conn, @recv_queue, @engine, @count_bytes

        parent.async(transient: true, annotation: "recv pump") do |task|
          loop do
            count = 0
            bytes = 0
            while count < FAIRNESS_MESSAGES && bytes < FAIRNESS_BYTES
              msg = conn.receive_message
              msg = transform.call(msg).freeze
              recv_queue.enqueue(msg)
              engine.emit_verbose_monitor_event(:message_received, parts: msg)
              count += 1
              bytes += msg.sum(&:bytesize) if count_bytes
            end
            task.yield
          end
        rescue Async::Stop, Async::Cancel
        rescue Protocol::ZMTP::Error, *CONNECTION_LOST
          # expected disconnect — supervisor will trigger teardown
        rescue => error
          @engine.signal_fatal_error(error)
        end
      end


      # Recv loop without transform — the hot path for native OMQ use.
      #
      # @param parent [Async::Task, Async::Barrier]
      # @return [Async::Task]
      #
      def start_direct(parent)
        conn, recv_queue, engine, count_bytes = @conn, @recv_queue, @engine, @count_bytes

        parent.async(transient: true, annotation: "recv pump") do |task|
          loop do
            count = 0
            bytes = 0
            while count < FAIRNESS_MESSAGES && bytes < FAIRNESS_BYTES
              msg = conn.receive_message
              recv_queue.enqueue(msg)
              engine.emit_verbose_monitor_event(:message_received, parts: msg)
              count += 1
              bytes += msg.sum(&:bytesize) if count_bytes
            end
            task.yield
          end
        rescue Async::Stop, Async::Cancel
        rescue Protocol::ZMTP::Error, *CONNECTION_LOST
          # expected disconnect — supervisor will trigger teardown
        rescue => error
          @engine.signal_fatal_error(error)
        end
      end

    end
  end
end
