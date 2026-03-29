# frozen_string_literal: true

module OMQ
  module ZMTP
    module Routing
      # REQ socket routing: round-robin send with strict send/recv alternation.
      #
      # REQ prepends an empty delimiter frame on send and strips it on receive.
      #
      class Req
        include RoundRobin

        # @param engine [Engine]
        #
        def initialize(engine)
          @engine     = engine
          @recv_queue = Async::LimitedQueue.new(engine.options.recv_hwm)
          @tasks      = []
          init_round_robin(engine)
        end

        # @return [Async::LimitedQueue]
        #
        attr_reader :recv_queue, :send_queue

        # @param connection [Connection]
        #
        def connection_added(connection)
          @connections << connection
          signal_connection_available
          task = @engine.start_recv_pump(connection, @recv_queue,
                   transform: method(:transform_recv))
          @tasks << task if task
          start_send_pump unless @send_pump_started
        end

        # @param connection [Connection]
        #
        def connection_removed(connection)
          @connections.delete(connection)
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

        # REQ prepends empty delimiter frame on the wire.
        #
        def transform_send(parts) = ["".b, *parts]

        # REQ strips the leading empty delimiter frame on receive.
        #
        def transform_recv(msg)
          msg.first&.empty? ? msg[1..] : msg
        end
      end
    end
  end
end
