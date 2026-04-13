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
        task = engine.spawn_conn_pump_task(conn, annotation: "send pump") do
          loop do
            batch = [q.dequeue]
            Routing.drain_send_queue(q, batch)

            if batch.size == 1
              conn.write_message batch.first
            else
              conn.write_messages batch
            end

            conn.flush

            batch.each { |parts| engine.emit_verbose_msg_sent(conn, parts) }
          end
        end

        tasks << task
        task
      end

    end
  end
end
