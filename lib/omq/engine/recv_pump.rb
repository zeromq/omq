# frozen_string_literal: true

module OMQ
  class Engine
    # Starts a recv pump for a connection.
    #
    # For inproc DirectPipe: wires the direct recv path (no fiber spawned).
    # For TCP/IPC: spawns a transient task that reads messages from the
    # connection and enqueues them into +recv_queue+.
    #
    # The two-branch structure (with/without transform) is intentional for
    # YJIT: it gives the JIT a monomorphic call per routing strategy instead
    # of a megamorphic `transform.call` dispatch inside a shared loop.
    #
    # @param parent_task [Async::Task]
    # @param conn [Connection, Transport::Inproc::DirectPipe]
    # @param recv_queue [SignalingQueue]
    # @param engine [Engine] for connection_lost / signal_fatal_error callbacks
    # @param transform [Proc, nil]
    # @return [Async::Task, nil]
    #
    class RecvPump
      FAIRNESS_MESSAGES = 64
      FAIRNESS_BYTES    = 1 << 20 # 1 MB

      def self.start(parent_task, conn, recv_queue, engine, transform)
        if conn.is_a?(Transport::Inproc::DirectPipe) && conn.peer
          conn.peer.direct_recv_queue     = recv_queue
          conn.peer.direct_recv_transform = transform
          return nil
        end

        if transform
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
            engine.connection_lost(conn)
          rescue => error
            engine.signal_fatal_error(error)
          end
        else
          parent_task.async(transient: true, annotation: "recv pump") do |task|
            loop do
              count = 0
              bytes = 0
              while count < FAIRNESS_MESSAGES && bytes < FAIRNESS_BYTES
                msg = conn.receive_message
                recv_queue.enqueue(msg)
                count += 1
                bytes += msg.is_a?(Array) && msg.first.is_a?(String) ? msg.sum(&:bytesize) : 0
              end
              task.yield
            end
          rescue Async::Stop
          rescue Protocol::ZMTP::Error, *CONNECTION_LOST
            engine.connection_lost(conn)
          rescue => error
            engine.signal_fatal_error(error)
          end
        end
      end
    end
  end
end
