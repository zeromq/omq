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
        attr_reader :subscriber_joined

        private

        def init_fan_out(engine)
          @connections        = []
          @subscriptions      = {} # connection => Set of prefixes
          @send_queue         = Async::LimitedQueue.new(engine.options.send_hwm)
          @send_pump_started  = false
          @send_pump_idle     = true
          @conflate           = engine.options.conflate
          @subscriber_joined  = Async::Promise.new
          @written            = Set.new
          @latest             = {} if @conflate
        end

        # @return [Boolean] whether the connection is subscribed to the topic
        #
        def subscribed?(conn, topic)
          subs = @subscriptions[conn]
          return false unless subs
          subs.any? { |prefix| topic.start_with?(prefix) }
        end

        # Called when a subscription command is received from a peer.
        # Override in subclasses to expose subscriptions to the
        # application (e.g. XPUB enqueues to recv_queue).
        #
        # @param conn [Connection]
        # @param prefix [String]
        #
        def on_subscribe(conn, prefix)
          @subscriptions[conn] << prefix.b.freeze
          @subscriber_joined.resolve(conn) unless @subscriber_joined.resolved?
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

        # @return [Boolean] true when the send pump is idle (not sending a batch)
        def send_pump_idle? = @send_pump_idle


        def start_send_pump
          @send_pump_started = true
          @tasks << @engine.spawn_pump_task(annotation: "send pump") do
            loop do
              @send_pump_idle = true
              batch = [@send_queue.dequeue]
              @send_pump_idle = false
              Routing.drain_send_queue(@send_queue, batch)

              @written.clear

              if @conflate
                # Keep only the last matching message per connection.
                @latest.clear
                batch.each do |parts|
                  topic = parts.first || EMPTY_BINARY
                  @connections.each do |conn|
                    next unless subscribed?(conn, topic)
                    @latest[conn] = parts
                  end
                end
                @latest.each do |conn, parts|
                  begin
                    conn.write_message(parts)
                    @written << conn
                  rescue *ZMTP::CONNECTION_LOST
                  end
                end
              else
                batch.each do |parts|
                  topic = parts.first || EMPTY_BINARY
                  @connections.each do |conn|
                    next unless subscribed?(conn, topic)
                    begin
                      conn.write_message(parts)
                      @written << conn
                    rescue *ZMTP::CONNECTION_LOST
                    end
                  end
                end
              end

              @written.each do |conn|
                conn.flush
              rescue *ZMTP::CONNECTION_LOST
              end
            end
          end
        end

        def start_subscription_listener(conn)
          @tasks << Reactor.spawn_pump(annotation: "recv pump") do
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
