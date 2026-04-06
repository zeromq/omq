# frozen_string_literal: true

module OMQ
  class Engine
    # Spawns a heartbeat task for a connection.
    #
    # Sends PING frames at +interval+ seconds and closes the connection
    # if no traffic is seen within +timeout+ seconds.
    #
    module Heartbeat
      # @param parent_task [Async::Task]
      # @param conn [Connection]
      # @param options [Options]
      # @param tasks [Array]
      #
      def self.start(parent_task, conn, options, tasks)
        interval = options.heartbeat_interval
        return unless interval

        ttl     = options.heartbeat_ttl     || interval
        timeout = options.heartbeat_timeout || interval
        conn.touch_heartbeat

        tasks << parent_task.async(transient: true, annotation: "heartbeat") do
          loop do
            sleep interval
            conn.send_command(Protocol::ZMTP::Codec::Command.ping(ttl: ttl, context: "".b))
            if conn.heartbeat_expired?(timeout)
              conn.close
              break
            end
          end
        rescue Async::Stop
        rescue *CONNECTION_LOST
          # connection closed
        end
      end
    end
  end
end
