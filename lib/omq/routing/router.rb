# frozen_string_literal: true

require "securerandom"
require "socket"

module OMQ
  module Routing
    # ROUTER socket routing: identity-based routing.
    #
    # Prepends peer identity frame on receive. Uses first frame as
    # routing identity on send.
    #
    class Router
      include FairRecv
      # @param engine [Engine]
      #
      def initialize(engine)
        @engine                  = engine
        @recv_queue              = FairQueue.new
        @connections_by_identity = {}
        @identity_by_connection  = {}
        @conn_queues             = {}  # connection => per-connection send queue
        @conn_send_tasks         = {}  # connection => send pump task
        @tasks                   = []
      end


      # @return [FairQueue]
      #
      attr_reader :recv_queue

      # @param connection [Connection]
      #
      def connection_added(connection)
        identity = connection.peer_identity
        identity = SecureRandom.bytes(5) if identity.nil? || identity.empty?
        @connections_by_identity[identity] = connection
        @identity_by_connection[connection] = identity

        add_fair_recv_connection(connection) { |msg| [identity, *msg] }

        q = Routing.build_queue(@engine.options.send_hwm, :block)
        @conn_queues[connection] = q
        @conn_send_tasks[connection] = ConnSendPump.start(@engine, connection, q, @tasks)
      end


      # @param connection [Connection]
      #
      def connection_removed(connection)
        identity = @identity_by_connection.delete(connection)
        @connections_by_identity.delete(identity) if identity
        @recv_queue.remove_queue(connection)
        @conn_queues.delete(connection)
        @conn_send_tasks.delete(connection)&.stop
      end


      # Enqueues a message for sending. The first frame is the routing identity.
      #
      # @param parts [Array<String>]
      #
      def enqueue(parts)
        identity = parts.first
        if @engine.options.router_mandatory?
          unless @connections_by_identity[identity]
            raise SocketError, "no route to identity #{identity.inspect}"
          end
        end
        conn = @connections_by_identity[identity]
        return unless conn  # silently drop if peer disconnected
        @conn_queues[conn]&.enqueue(parts[1..])
      end


      # Stops all background tasks.
      #
      # @return [void]
      #
      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end


      # @return [Boolean] true when all per-connection send queues are empty
      #
      def send_queues_drained?
        @conn_queues.values.all?(&:empty?)
      end

    end
  end
end
