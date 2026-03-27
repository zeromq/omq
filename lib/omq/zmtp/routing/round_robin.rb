# frozen_string_literal: true

module OMQ
  module ZMTP
    module Routing
      # Mixin for routing strategies that send via round-robin.
      #
      # Provides reactive connection management: Async::Promise waits
      # for the first connection, Array#cycle handles round-robin,
      # and a new Promise is created when all connections drop.
      #
      # Including classes must call `init_round_robin(engine)` from
      # their #initialize.
      #
      module RoundRobin
        private

        def init_round_robin(engine)
          @connections          = []
          @cycle                = @connections.cycle
          @connection_available = Async::Promise.new
          @send_queue           = Async::LimitedQueue.new(engine.options.send_hwm)
          @send_pump_started    = false
        end

        def signal_connection_available
          unless @connection_available.resolved?
            @connection_available.resolve(true)
          end
        end

        # Blocks until a connection is available, then returns
        # the next one in round-robin order.
        #
        # @return [Connection]
        #
        def next_connection
          @cycle.next
        rescue StopIteration
          @connection_available = Async::Promise.new
          @connection_available.wait
          @cycle = @connections.cycle
          retry
        end

        # Transforms parts before sending. Override in subclasses
        # (e.g. REQ prepends an empty delimiter frame).
        #
        # @param parts [Array<String>]
        # @return [Array<String>]
        #
        def transform_send(parts) = parts

        def start_send_pump
          @send_pump_started = true
          @tasks << Reactor.spawn_pump do
            loop do
              parts = @send_queue.dequeue
              send_with_retry(parts)
            end
          end
        end

        def send_with_retry(parts)
          conn = next_connection
          conn.send_message(transform_send(parts))
        rescue *ZMTP::CONNECTION_LOST
          @engine.connection_lost(conn)
          retry
        end
      end
    end
  end
end
