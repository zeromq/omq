# frozen_string_literal: true

module OMQ
  module ZMTP
    module Routing
      # XPUB socket routing: like PUB but exposes subscription messages.
      #
      # Subscription/unsubscription messages from peers are delivered to
      # the application as data frames: \x01 + prefix for subscribe,
      # \x00 + prefix for unsubscribe.
      #
      class XPub
        include FanOut

        # @param engine [Engine]
        #
        def initialize(engine)
          @engine     = engine
          @recv_queue = Async::LimitedQueue.new(engine.options.recv_hwm)
          @tasks      = []
          init_fan_out(engine)
        end

        # @return [Async::LimitedQueue]
        #
        attr_reader :recv_queue, :send_queue

        # @param connection [Connection]
        #
        def connection_added(connection)
          @connections << connection
          @subscriptions[connection] = Set.new
          start_subscription_listener(connection)
          start_send_pump unless @send_pump_started
        end

        # @param connection [Connection]
        #
        def connection_removed(connection)
          @connections.delete(connection)
          @subscriptions.delete(connection)
        end

        # @param parts [Array<String>]
        #
        def enqueue(parts)
          @send_queue.enqueue(parts)
        end

        #
        def stop
          @tasks.each(&:stop)
          @tasks.clear
        end

        private

        # Expose subscription to application as data message.
        #
        def on_subscribe(conn, prefix)
          super
          @recv_queue.enqueue(["\x01#{prefix}".b])
        end

        # Expose unsubscription to application as data message.
        #
        def on_cancel(conn, prefix)
          super
          @recv_queue.enqueue(["\x00#{prefix}".b])
        end
      end
    end
  end
end
