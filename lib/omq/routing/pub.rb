# frozen_string_literal: true

module OMQ
  module Routing
    # PUB socket routing: fan-out to all subscribers.
    #
    # Listens for SUBSCRIBE/CANCEL commands from peers.
    # Drops messages if a subscriber's connection write fails.
    #
    class Pub
      include FanOut

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine = engine
        @tasks  = []
        init_fan_out(engine)
      end

      # @return [Async::LimitedQueue]
      #
      attr_reader :send_queue

      # PUB is write-only.
      #
      def recv_queue
        raise "PUB sockets cannot receive"
      end

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
    end
  end
end
