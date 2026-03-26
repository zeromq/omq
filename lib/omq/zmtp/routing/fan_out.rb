# frozen_string_literal: true

module OMQ
  module ZMTP
    module Routing
      # Mixin for routing strategies that fan-out to subscribers.
      #
      # Manages per-connection subscription sets, subscription command
      # listeners, and a send pump that delivers to all matching peers.
      #
      # Including classes must call `init_fan_out(engine)` from
      # their #initialize.
      #
      module FanOut
        private

        def init_fan_out(engine)
          @connections        = []
          @subscriptions      = {} # connection => Set of prefixes
          @send_queue         = Async::LimitedQueue.new(engine.options.send_hwm)
          @send_pump_started  = false
        end

        # @return [Boolean] whether the connection is subscribed to the topic
        #
        def subscribed?(conn, topic)
          subs = @subscriptions[conn]
          return false unless subs
          subs.any? { |prefix| topic.b.start_with?(prefix.b) }
        end

        # Called when a subscription command is received from a peer.
        # Override in subclasses to expose subscriptions to the
        # application (e.g. XPUB enqueues to recv_queue).
        #
        # @param conn [Connection]
        # @param prefix [String]
        #
        def on_subscribe(conn, prefix)
          @subscriptions[conn] << prefix
        end

        # Called when a cancel command is received from a peer.
        # Override in subclasses (e.g. XPUB enqueues to recv_queue).
        #
        # @param conn [Connection]
        # @param prefix [String]
        #
        def on_cancel(conn, prefix)
          @subscriptions[conn]&.delete(prefix)
        end

        def start_send_pump
          @send_pump_started = true
          @tasks << Reactor.spawn_pump do
            loop do
              parts = @send_queue.dequeue
              topic = parts.first || "".b
              @connections.each do |conn|
                next unless subscribed?(conn, topic)
                begin
                  conn.send_message(parts)
                rescue *ZMTP::CONNECTION_LOST
                  # connection dead — will be cleaned up
                end
              end
            end
          end
        end

        def start_subscription_listener(conn)
          @tasks << Reactor.spawn_pump do
            loop do
              frame = conn.read_frame
              next unless frame.command?
              cmd = Codec::Command.from_body(frame.body)
              case cmd.name
              when "SUBSCRIBE" then on_subscribe(conn, cmd.data)
              when "CANCEL"    then on_cancel(conn, cmd.data)
              end
            end
          rescue *ZMTP::CONNECTION_LOST
            @engine.connection_lost(conn)
          end
        end
      end
    end
  end
end
