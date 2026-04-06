# frozen_string_literal: true

module OMQ
  module Routing
    # Starts a dedicated send pump for one per-connection send queue.
    #
    # Used by Router and Rep, which have per-connection queues but do not
    # include the RoundRobin mixin.
    #
    module ConnSendPump
      # Spawns the pump task and registers it in +tasks+.
      #
      # @param engine [Engine]
      # @param conn [Connection]
      # @param q [Async::LimitedQueue]
      # @param tasks [Array]
      # @return [Async::Task]
      #
      def self.start(engine, conn, q, tasks)
        task = engine.spawn_pump_task(annotation: "send pump") do
          loop do
            batch = [q.dequeue]
            Routing.drain_send_queue(q, batch)
            batch.each { |parts| conn.write_message(parts) }
            conn.flush
          rescue Protocol::ZMTP::Error, *CONNECTION_LOST
            engine.connection_lost(conn)
            break
          end
        end
        tasks << task
        task
      end
    end
  end
end
