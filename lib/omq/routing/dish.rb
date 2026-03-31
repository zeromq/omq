# frozen_string_literal: true

module OMQ
  module Routing
    # DISH socket routing: group-based receive from RADIO peers.
    #
    # Sends JOIN/LEAVE commands to connected RADIO peers.
    # Receives two-frame messages (group + body) from RADIO.
    #
    class Dish

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine      = engine
        @connections = []
        @recv_queue  = Async::LimitedQueue.new(engine.options.recv_hwm)
        @groups      = Set.new
        @tasks       = []
      end

      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue

      # @param connection [Connection]
      #
      def connection_added(connection)
        @connections << connection
        # Send existing group memberships to new peer
        @groups.each do |group|
          connection.send_command(Protocol::ZMTP::Codec::Command.join(group))
        end
        task = @engine.start_recv_pump(connection, @recv_queue)
        @tasks << task if task
      end

      # @param connection [Connection]
      #
      def connection_removed(connection)
        @connections.delete(connection)
      end

      # DISH is read-only.
      #
      def enqueue(_parts)
        raise "DISH sockets cannot send"
      end

      # Joins a group.
      #
      # @param group [String]
      #
      def join(group)
        @groups << group
        @connections.each do |conn|
          conn.send_command(Protocol::ZMTP::Codec::Command.join(group))
        end
      end

      # Leaves a group.
      #
      # @param group [String]
      #
      def leave(group)
        @groups.delete(group)
        @connections.each do |conn|
          conn.send_command(Protocol::ZMTP::Codec::Command.leave(group))
        end
      end

      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end
    end
  end
end
