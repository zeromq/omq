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
      FAIRNESS_MESSAGES = 64
      FAIRNESS_BYTES    = 1 << 20 # 1 MB

      # Public entry point — callers use the class method.
      #
      # @param parent_task [Async::Task]
      # @param conn [Connection, Transport::Inproc::DirectPipe]
      # @param recv_queue [SignalingQueue]
      # @param engine [Engine]
      # @param transform [Proc, nil]
      # @return [Async::Task, nil]
      #
      def self.start(parent_task, conn, recv_queue, engine, transform)
        new(conn, recv_queue, engine).start(parent_task, transform)
      end

      def initialize(conn, recv_queue, engine)
        @conn       = conn
        @recv_queue = recv_queue
        @engine     = engine
      end

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

      def start_with_transform(parent_task, transform)
        conn, recv_queue = @conn, @recv_queue

        parent_task.async(transient: true, annotation: "recv pump") do |task|
          loop do
            count = 0
            bytes = 0
            while count < FAIRNESS_MESSAGES && bytes < FAIRNESS_BYTES
              msg = conn.receive_message
              msg = transform.call(msg).freeze
              recv_queue.enqueue(msg)
              count += 1
              bytes += msg.is_a?(Array) && msg.first.is_a?(String) ? msg.sum(&:bytesize) : 0
            end
            task.yield
          end
        rescue Async::Stop
        rescue Protocol::ZMTP::Error, *CONNECTION_LOST
          @engine.connection_lost(conn)
        rescue => error
          @engine.signal_fatal_error(error)
        end
      end

      def start_direct(parent_task)
        conn, recv_queue = @conn, @recv_queue

        parent_task.async(transient: true, annotation: "recv pump") do |task|
          loop do
            count = 0
            bytes = 0
            while count < FAIRNESS_MESSAGES && bytes < FAIRNESS_BYTES
              msg = conn.receive_message
              recv_queue.enqueue(msg)
              count += 1
              bytes += msg.sum(&:bytesize)
            end
            task.yield
          end
        rescue Async::Stop
        rescue Protocol::ZMTP::Error, *CONNECTION_LOST
          @engine.connection_lost(conn)
        rescue => error
          @engine.signal_fatal_error(error)
        end
      end
    end
  end
end
