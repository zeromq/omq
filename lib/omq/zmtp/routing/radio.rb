# frozen_string_literal: true

module OMQ
  module ZMTP
    module Routing
      # RADIO socket routing: group-based fan-out to DISH peers.
      #
      # Like PUB/FanOut but with exact group matching and JOIN/LEAVE
      # commands instead of SUBSCRIBE/CANCEL.
      #
      # Messages are sent as two frames on the wire:
      #   group (MORE=1) + body (MORE=0)
      #
      class Radio

        # @param engine [Engine]
        #
        def initialize(engine)
          @engine            = engine
          @connections       = []
          @groups            = {} # connection => Set of joined groups
          @send_queue        = Async::LimitedQueue.new(engine.options.send_hwm)
          @send_pump_started = false
          @conflate          = engine.options.conflate
          @tasks             = []
        end

        # @return [Async::LimitedQueue]
        #
        attr_reader :send_queue

        # RADIO is write-only.
        #
        def recv_queue
          raise "RADIO sockets cannot receive"
        end

        # @param connection [Connection]
        #
        def connection_added(connection)
          @connections << connection
          @groups[connection] = Set.new
          start_group_listener(connection)
          start_send_pump unless @send_pump_started
        end

        # @param connection [Connection]
        #
        def connection_removed(connection)
          @connections.delete(connection)
          @groups.delete(connection)
        end

        # Enqueues a message for sending.
        #
        # @param parts [Array<String>] [group, body]
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
          @tasks << @engine.parent_task.async(transient: true, annotation: "send pump") do
            loop do
              @send_pump_idle = true
              batch = [@send_queue.dequeue]
              @send_pump_idle = false
              Routing.drain_send_queue(@send_queue, batch)

              written = Set.new

              if @conflate
                # Keep only the last matching message per connection.
                latest = {} # conn => [group, body]
                batch.each do |parts|
                  group = parts[0]
                  body  = parts[1] || "".b
                  @connections.each do |conn|
                    next unless @groups[conn]&.include?(group)
                    latest[conn] = [group, body]
                  end
                end
                latest.each do |conn, msg|
                  begin
                    conn.write_message(msg)
                    written << conn
                  rescue *ZMTP::CONNECTION_LOST
                  end
                end
              else
                batch.each do |parts|
                  group = parts[0]
                  body  = parts[1] || "".b
                  @connections.each do |conn|
                    next unless @groups[conn]&.include?(group)
                    begin
                      conn.write_message([group, body])
                      written << conn
                    rescue *ZMTP::CONNECTION_LOST
                    end
                  end
                end
              end

              written.each do |conn|
                conn.flush
              rescue *ZMTP::CONNECTION_LOST
              end
            end
          end
        end

        def start_group_listener(conn)
          @tasks << Reactor.spawn_pump(annotation: "recv pump") do
            loop do
              frame = conn.read_frame
              next unless frame.command?
              cmd = Codec::Command.from_body(frame.body)
              case cmd.name
              when "JOIN"  then @groups[conn]&.add(cmd.data)
              when "LEAVE" then @groups[conn]&.delete(cmd.data)
              end
            end
          rescue *ZMTP::CONNECTION_LOST
            @engine.connection_lost(conn)
          end
        end
      end
    end
  end
end
