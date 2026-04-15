# frozen_string_literal: true

module OMQ
  module Routing
    # SUB socket routing: subscription-based receive from PUB peers.
    #
    # Sends SUBSCRIBE/CANCEL commands to connected PUB peers.
    #
    class Sub

      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue


      # @param engine [Engine]
      #
      def initialize(engine)
        @engine        = engine
        @connections   = Set.new
        @recv_queue    = Routing.build_queue(engine.options.recv_hwm, :block)
        @subscriptions = Set.new
        @tasks         = []
      end


      # Dequeues the next received message. Blocks until one is available.
      #
      # @return [Array<String>, nil]
      #
      def dequeue_recv
        @recv_queue.dequeue
      end


      # Wakes a blocked {#dequeue_recv} with a nil sentinel.
      #
      # @return [void]
      #
      def unblock_recv
        @recv_queue.enqueue(nil)
      end


      # @param connection [Connection]
      #
      def connection_added(connection)
        @connections << connection

        @subscriptions.each do |prefix|
          connection.send_command(Protocol::ZMTP::Codec::Command.subscribe(prefix))
        end

        task = @engine.start_recv_pump(connection, @recv_queue)
        @tasks << task if task
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        @connections.delete(connection)
      end


      # SUB is read-only.
      #
      def enqueue(_parts)
        raise "SUB sockets cannot send"
      end


      # Subscribes to a topic prefix.
      #
      # @param prefix [String]
      #
      def subscribe(prefix)
        @subscriptions << prefix
        @connections.each do |conn|
          conn.send_command(Protocol::ZMTP::Codec::Command.subscribe(prefix))
        end
      end


      # Unsubscribes from a topic prefix.
      #
      # @param prefix [String]
      #
      def unsubscribe(prefix)
        @subscriptions.delete(prefix)
        @connections.each do |conn|
          conn.send_command(Protocol::ZMTP::Codec::Command.cancel(prefix))
        end
      end


      # Stops all background tasks.
      #
      # @return [void]
      #
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end

    end
  end
end
