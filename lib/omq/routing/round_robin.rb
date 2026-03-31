# frozen_string_literal: true

module OMQ
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


      # Initializes round-robin state for the including class.
      #
      # @param engine [Engine]
      #
      def init_round_robin(engine)
        @connections          = []
        @cycle                = @connections.cycle
        @connection_available = Async::Promise.new
        @send_queue           = Async::LimitedQueue.new(engine.options.send_hwm)
        @send_pump_started    = false
        @send_pump_idle       = true
        @written              = Set.new
      end


      # Resolves the connection-available promise so blocked
      # senders can proceed.
      #
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


      # Starts the background send pump that dequeues messages
      # and dispatches them round-robin across connections.
      #
      # @return [Boolean] true when the send pump is idle (not sending a batch)
      def send_pump_idle? = @send_pump_idle


      def start_send_pump
        @send_pump_started = true
        @tasks << @engine.spawn_pump_task(annotation: "send pump") do
          loop do
            @send_pump_idle = true
            batch = [@send_queue.dequeue]
            @send_pump_idle = false
            Routing.drain_send_queue(@send_queue, batch)

            if batch.size == 1
              send_with_retry(batch[0])
            else
              send_batch(batch)
            end
          end
        end
      end


      # Sends a single message, retrying on a new connection if
      # the current one is lost.
      #
      # @param parts [Array<String>]
      #
      def send_with_retry(parts)
        conn = next_connection
        conn.send_message(transform_send(parts))
      rescue *CONNECTION_LOST
        @engine.connection_lost(conn)
        retry
      end


      # Sends a batch of messages, writing without flushing for
      # throughput. Falls back to #send_with_retry on failure.
      #
      # @param batch [Array<Array<String>>]
      #
      def send_batch(batch)
        @written.clear
        batch.each_with_index do |parts, i|
          conn = next_connection
          begin
            conn.write_message(transform_send(parts))
            @written << conn
          rescue *CONNECTION_LOST
            @engine.connection_lost(conn)
            # Flush what we've written so far
            @written.each do |c|
              c.flush
            rescue *CONNECTION_LOST
              # will be cleaned up
            end
            @written.clear
            # Fall back to send_with_retry for this and remaining
            send_with_retry(parts)
            batch[(i + 1)..].each { |p| send_with_retry(p) }
            return
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
