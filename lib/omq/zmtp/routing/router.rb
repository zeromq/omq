# frozen_string_literal: true

require "securerandom"
require "socket"

module OMQ
  module ZMTP
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
          @tasks                   = []
          @send_pump_started       = false
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

          task = @engine.start_recv_pump(connection, @recv_queue,
                   transform: ->(msg) { [identity, *msg] })
          @tasks << task if task

          start_send_pump unless @send_pump_started
        end

        # @param connection [Connection]
        #
        def connection_removed(connection)
          @connections_by_identity.reject! { |_, c| c == connection }
        end

        # Enqueues a message for sending.
        #
        # @param parts [Array<String>]
        #
        def enqueue(parts)
          @send_queue.enqueue(parts)
        end

        def stop
          @tasks.each(&:stop)
          @tasks.clear
        end

        private

        def start_send_pump
          @send_pump_started = true
          @tasks << Reactor.spawn_pump do
            loop do
              parts = @send_queue.dequeue
              identity = parts.first
              conn = @connections_by_identity[identity]

              unless conn
                if @engine.options.router_mandatory?
                  raise SocketError, "no route to identity #{identity.inspect}"
                end
                next # silently drop
              end

              # Send everything after the identity frame
              conn.send_message(parts[1..])
            end
          end
        end
      end
    end
  end
end
