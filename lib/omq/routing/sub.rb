# frozen_string_literal: true

module OMQ
  module Routing
    # SUB socket routing: subscription-based receive from PUB peers.
    #
    # Sends SUBSCRIBE/CANCEL commands to connected PUB peers.
    #
    class Sub

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine        = engine
        @connections   = Set.new
        @recv_queue    = FairQueue.new
        @subscriptions = Set.new
        @tasks         = []
      end


      # @return [FairQueue]
      #
      attr_reader :recv_queue

      # @param connection [Connection]
      #
      def connection_added(connection)
        @connections << connection
        @subscriptions.each do |prefix|
          connection.send_command(Protocol::ZMTP::Codec::Command.subscribe(prefix))
        end
        conn_q    = Routing.build_queue(@engine.options.recv_hwm, @engine.options.on_mute)
        signaling = SignalingQueue.new(conn_q, @recv_queue)
        @recv_queue.add_queue(connection, conn_q)
        task = @engine.start_recv_pump(connection, signaling)
        @tasks << task if task
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        @connections.delete(connection)
        @recv_queue.remove_queue(connection)
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
