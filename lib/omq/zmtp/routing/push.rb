# frozen_string_literal: true

module OMQ
  module ZMTP
    module Routing
      # PUSH socket routing: round-robin send to PULL peers.
      #
      class Push
        include RoundRobin

        # @param engine [Engine]
        #
        def initialize(engine)
          @engine = engine
          @tasks  = []
          init_round_robin(engine)
        end

        # @return [Async::LimitedQueue]
        #
        attr_reader :send_queue

        # PUSH is write-only.
        #
        def recv_queue
          raise "PUSH sockets cannot receive"
        end

        # @param connection [Connection]
        #
        def connection_added(connection)
          @connections << connection
          signal_connection_available
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
      end
    end
  end
end
