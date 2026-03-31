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
      # @param engine [Engine]
      #
      def initialize(engine)
        @engine                  = engine
        @recv_queue              = Async::LimitedQueue.new(engine.options.recv_hwm)
        @send_queue              = Async::LimitedQueue.new(engine.options.send_hwm)
        @connections_by_identity = {}
        @identity_by_connection  = {}
        @tasks                   = []
        @send_pump_started       = false
        @send_pump_idle          = true
        @written                 = Set.new
      end

      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue, :send_queue

      # @param connection [Connection]
      #
      def connection_added(connection)
        identity = connection.peer_identity
        identity = SecureRandom.bytes(5) if identity.nil? || identity.empty?
        @connections_by_identity[identity] = connection
        @identity_by_connection[connection] = identity

        task = @engine.start_recv_pump(connection, @recv_queue) do |msg|
          [identity, *msg]
        end
        @tasks << task if task

        start_send_pump unless @send_pump_started
      end

      # @param connection [Connection]
      #
      def connection_removed(connection)
        identity = @identity_by_connection.delete(connection)
        @connections_by_identity.delete(identity) if identity
      end

      # Enqueues a message for sending.
      #
      # @param parts [Array<String>]
      #
      def enqueue(parts)
        if @engine.options.router_mandatory?
          identity = parts.first
          unless @connections_by_identity[identity]
            raise SocketError, "no route to identity #{identity.inspect}"
          end
        end
        @send_queue.enqueue(parts)
      end

      def stop
        @tasks.each(&:stop)
        @tasks.clear
      end

      private

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
            batch.each do |parts|
              identity = parts.first
              conn     = @connections_by_identity[identity]
              next unless conn # silently drop (peer may have disconnected)
              begin
                conn.write_message(parts[1..])
                @written << conn
              rescue *CONNECTION_LOST
                # will be cleaned up
              end
            end

            @written.each do |conn|
              conn.flush
            rescue *CONNECTION_LOST
              # will be cleaned up
            end
          end
        end
      end
    end
  end
end
