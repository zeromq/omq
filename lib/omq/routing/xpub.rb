# frozen_string_literal: true

module OMQ
  module Routing
    # XPUB socket routing: like PUB but exposes subscription messages.
    #
    # Subscription/unsubscription messages from peers are delivered to
    # the application as data frames: \x01 + prefix for subscribe,
    # \x00 + prefix for unsubscribe.
    #
    # The recv_queue is a simple bounded queue (not a FairQueue) because
    # messages come from subscription commands, not from peer data pumps.
    #
    class XPub
      include FanOut

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine     = engine
        @recv_queue = Routing.build_queue(engine.options.recv_hwm, :block)
        @tasks      = []
        init_fan_out(engine)
      end


      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue

      # @param connection [Connection]
      #
      def connection_added(connection)
        @connections << connection
        @subscriptions[connection] = Set.new
        start_subscription_listener(connection)
        add_fan_out_send_connection(connection)
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        @connections.delete(connection)
        @subscriptions.delete(connection)
        remove_fan_out_send_connection(connection)
      end


      # @param parts [Array<String>]
      #
      def enqueue(parts)
        fan_out_enqueue(parts)
      end


      # Stops all background tasks.
      #
      # @return [void]
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
