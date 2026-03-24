# frozen_string_literal: true

module OMQ
  module ZMTP
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
          @connections   = []
          @recv_queue    = Async::LimitedQueue.new(engine.options.recv_hwm)
          @subscriptions = Set.new
          @tasks         = []
        end

        # @return [Async::LimitedQueue]
        #
        attr_reader :recv_queue

        # @param connection [Connection]
        #
        def connection_added(connection)
          @connections << connection
          # Send existing subscriptions to new peer
          @subscriptions.each do |prefix|
            connection.send_command(Codec::Command.subscribe(prefix))
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
            conn.send_command(Codec::Command.subscribe(prefix))
          end
        end

        # Unsubscribes from a topic prefix.
        #
        # @param prefix [String]
        #
        def unsubscribe(prefix)
          @subscriptions.delete(prefix)
          @connections.each do |conn|
            conn.send_command(Codec::Command.cancel(prefix))
          end
        end

        def stop
          @tasks.each(&:stop)
          @tasks.clear
        end

      end
    end
  end
end
