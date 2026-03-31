# frozen_string_literal: true

module OMQ
  module Routing
    # XSUB socket routing: like SUB but subscriptions sent as data messages.
    #
    # Subscriptions are sent as data frames: \x01 + prefix for subscribe,
    # \x00 + prefix for unsubscribe.
    #
    class XSub

      # @param engine [Engine]
      #
      def initialize(engine)
        @engine            = engine
        @connections       = []
        @recv_queue        = Async::LimitedQueue.new(engine.options.recv_hwm)
        @send_queue        = Async::LimitedQueue.new(engine.options.send_hwm)
        @tasks             = []
        @send_pump_started = false
        @send_pump_idle    = true
      end

      # @return [Async::LimitedQueue]
      #
      attr_reader :recv_queue, :send_queue

      # @param connection [Connection]
      #
      def connection_added(connection)
        @connections << connection
        task = @engine.start_recv_pump(connection, @recv_queue)
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

      def send_pump_idle? = @send_pump_idle


      def start_send_pump
        @send_pump_started = true
        @tasks << @engine.spawn_pump_task(annotation: "send pump") do
          loop do
            @send_pump_idle = true
            parts = @send_queue.dequeue
            @send_pump_idle = false
            frame = parts.first&.b
            next if frame.nil? || frame.empty?

            flag   = frame.getbyte(0)
            prefix = frame.byteslice(1..) || "".b

            case flag
            when 0x01
              @connections.each { |c| c.send_command(Protocol::ZMTP::Codec::Command.subscribe(prefix)) }
            when 0x00
              @connections.each { |c| c.send_command(Protocol::ZMTP::Codec::Command.cancel(prefix)) }
            end
          end
        end
      end
    end
  end
end
