# frozen_string_literal: true

require "securerandom"

module OMQ
  module Routing
    # PEER socket routing: bidirectional multi-peer with auto-generated
    # 4-byte routing IDs.
    #
    # Prepends routing ID on receive. Strips routing ID on send and
    # routes to the identified connection.
    #
    class Peer
      # @param engine [Engine]
      #
      def initialize(engine)
        @engine                     = engine
        @recv_queue                 = Async::LimitedQueue.new(engine.options.recv_hwm)
        @send_queue                 = Async::LimitedQueue.new(engine.options.send_hwm)
        @connections_by_routing_id  = {}
        @routing_id_by_connection   = {}
        @tasks                      = []
        @send_pump_started          = false
        @send_pump_idle             = true
        @written                    = Set.new
      end

      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue, :send_queue

      # @param connection [Connection]
      #
      def connection_added(connection)
        routing_id = SecureRandom.bytes(4)
        @connections_by_routing_id[routing_id] = connection
        @routing_id_by_connection[connection]  = routing_id

        task = @engine.start_recv_pump(connection, @recv_queue) do |msg|
          [routing_id, *msg]
        end
        @tasks << task if task

        start_send_pump unless @send_pump_started
      end

      # @param connection [Connection]
      #
      def connection_removed(connection)
        routing_id = @routing_id_by_connection.delete(connection)
        @connections_by_routing_id.delete(routing_id) if routing_id
      end

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
              routing_id = parts.first
              conn       = @connections_by_routing_id[routing_id]
              next unless conn # silently drop if peer gone
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
