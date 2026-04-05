# frozen_string_literal: true

module OMQ
  class Engine
    # Schedules reconnect attempts with exponential back-off.
    #
    # Runs a background task that loops until a connection is established
    # or the engine is closed.
    #
    class Reconnect
      # @param endpoint [String]
      # @param options [Options]
      # @param parent_task [Async::Task]
      # @param engine [Engine] for transport_for / emit_monitor_event / signal_fatal_error / closed?
      # @param delay [Numeric, nil] initial delay (defaults to reconnect_interval)
      #
      def self.schedule(endpoint, options, parent_task, engine, delay: nil)
        ri = options.reconnect_interval
        delay, max_delay = init_delay(ri, delay)

        engine.tasks << parent_task.async(transient: true, annotation: "reconnect #{endpoint}") do
          loop do
            break if engine.closed?
            sleep delay if delay > 0
            break if engine.closed?
            begin
              engine.transport_for(endpoint).connect(endpoint, engine)
              break
            rescue *CONNECTION_LOST, *CONNECTION_FAILED, Protocol::ZMTP::Error
              delay = next_delay(delay, max_delay, ri)
              engine.emit_monitor_event(:connect_retried, endpoint: endpoint, detail: { interval: delay })
            end
          end
        rescue Async::Stop
        rescue => error
          engine.signal_fatal_error(error)
        end
      end

      def self.init_delay(ri, delay)
        if ri.is_a?(Range)
          [delay || ri.begin, ri.end]
        else
          [delay || ri, nil]
        end
      end

      def self.next_delay(delay, max_delay, ri)
        delay = delay * 2
        delay = [delay, max_delay].min if max_delay
        delay = (ri.is_a?(Range) ? ri.begin : ri) if delay == 0
        delay
      end
    end
  end
end
