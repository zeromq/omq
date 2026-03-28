# frozen_string_literal: true

require "securerandom"

module OMQ
  module ZMTP
    module Routing
      # SERVER socket routing: identity-based routing with auto-generated
      # 4-byte routing IDs.
      #
      # Prepends routing ID on receive. Strips routing ID on send and
      # routes to the identified connection.
      #
      class Server
        # @param engine [Engine]
        #
        def initialize(engine)
          @engine                     = engine
          @recv_queue                 = Async::LimitedQueue.new(engine.options.recv_hwm)
          @send_queue                 = Async::LimitedQueue.new(engine.options.send_hwm)
          @connections_by_routing_id  = {}
          @tasks                      = []
          @send_pump_started          = false
        end

        # @return [Async::LimitedQueue]
        #
        attr_reader :recv_queue, :send_queue

        # @param connection [Connection]
        #
        def connection_added(connection)
          routing_id = SecureRandom.bytes(4)
          @connections_by_routing_id[routing_id] = connection

          task = @engine.start_recv_pump(connection, @recv_queue,
                   transform: ->(msg) { [routing_id, *msg] })
          @tasks << task if task

          start_send_pump unless @send_pump_started
        end

        # @param connection [Connection]
        #
        def connection_removed(connection)
          @connections_by_routing_id.reject! { |_, c| c == connection }
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

        def start_send_pump
          @send_pump_started = true
          @tasks << Reactor.spawn_pump do
            loop do
              batch = [@send_queue.dequeue]
              Routing.drain_send_queue(@send_queue, batch)

              written = []
              batch.each do |parts|
                routing_id = parts.first
                conn       = @connections_by_routing_id[routing_id]
                next unless conn # silently drop if peer gone
                begin
                  conn.write_message(parts[1..])
                  written << conn
                rescue *ZMTP::CONNECTION_LOST
                  # will be cleaned up
                end
              end
              written.uniq!
              written.each { |conn| conn.flush rescue nil }
            end
          end
        end
      end
    end
  end
end
