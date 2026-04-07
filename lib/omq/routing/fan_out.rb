# frozen_string_literal: true

module OMQ
  module Routing
    # Mixin for routing strategies that fan-out to subscribers.
    #
    # Manages per-connection subscription sets, subscription command
    # listeners, and per-connection send queues/pumps that deliver
    # to each matching peer independently.
    #
    # HWM is enforced per subscriber: each connection gets its own
    # bounded send queue. DropQueues (for :drop_newest/:drop_oldest)
    # silently drop messages for a slow subscriber without affecting
    # others. LimitedQueues (for :block) block the publisher.
    #
    # Including classes must call `init_fan_out(engine)` from
    # their #initialize.
    #
    module FanOut
      # @return [Async::Promise] resolves when the first subscriber joins
      #
      attr_reader :subscriber_joined

      # @return [Boolean] true when all per-connection send queues are empty
      #
      def send_queues_drained?
        @conn_queues.values.all?(&:empty?)
      end

      private

      def init_fan_out(engine)
        @connections        = Set.new
        @subscriptions      = {} # connection => Set of prefixes
        @subscribe_all      = Set.new # connections subscribed to "" (match-all fast path)
        @conn_queues        = {} # connection => per-connection send queue
        @conn_send_tasks    = {} # connection => send pump task
        @conflate           = engine.options.conflate
        @subscriber_joined  = Async::Promise.new
        @latest             = {} if @conflate
      end


      # @return [Boolean] whether the connection is subscribed to the topic
      #
      def subscribed?(conn, topic)
        return true if @subscribe_all.include?(conn)
        subs = @subscriptions[conn]
        return false unless subs
        subs.any? { |prefix| topic.start_with?(prefix) }
      end


      # Called when a subscription command is received from a peer.
      # Override in subclasses to expose subscriptions to the
      # application (e.g. XPUB enqueues to recv_queue).
      #
      # @param conn [Connection]
      # @param prefix [String]
      #
      def on_subscribe(conn, prefix)
        @subscriptions[conn] << prefix.b.freeze
        @subscribe_all.add(conn) if prefix.empty?
        @subscriber_joined.resolve(conn) unless @subscriber_joined.resolved?
      end


      # Called when a cancel command is received from a peer.
      # Override in subclasses (e.g. XPUB enqueues to recv_queue).
      #
      # @param conn [Connection]
      # @param prefix [String]
      #
      def on_cancel(conn, prefix)
        @subscriptions[conn]&.delete(prefix)
        @subscribe_all.delete(conn) if prefix.empty?
      end


      # Creates a per-connection send queue and starts its send pump.
      # Call from #connection_added.
      #
      # @param conn [Connection]
      #
      def add_fan_out_send_connection(conn)
        q = Routing.build_queue(@engine.options.send_hwm, :block)
        @conn_queues[conn] = q
        start_conn_send_pump(conn, q)
      end


      # Stops the per-connection send pump and removes the queue.
      # Call from #connection_removed.
      #
      # @param conn [Connection]
      #
      def remove_fan_out_send_connection(conn)
        @subscribe_all.delete(conn)
        @conn_queues.delete(conn)
        @conn_send_tasks.delete(conn)&.stop
      end


      # Fans a message out to every connected peer's send queue.
      # Subscription filtering happens in the per-connection send pump so
      # that late-arriving subscriptions (e.g. inproc connect-before-subscribe)
      # are respected: a message enqueued before the async subscription listener
      # has processed SUBSCRIBE commands will still be delivered correctly.
      #
      # Per-connection queues use :block (Async::LimitedQueue) for
      # backpressure: when a subscriber's queue is full, the publisher
      # yields until the send pump drains it. This matches the old
      # shared-queue behavior and keeps the publisher fiber-friendly.
      #
      # @param parts [Array<String>]
      #
      def fan_out_enqueue(parts)
        @connections.each do |conn|
          @conn_queues[conn].enqueue(parts)
        end
      end


      def start_subscription_listener(conn)
        @tasks << @engine.spawn_pump_task(annotation: "subscription listener") do
          loop do
            frame = conn.read_frame
            next unless frame.command?
            cmd = Protocol::ZMTP::Codec::Command.from_body(frame.body)
            case cmd.name
            when "SUBSCRIBE"
              on_subscribe(conn, cmd.data)
            when "CANCEL"
              on_cancel(conn, cmd.data)
            end
          end
        rescue *CONNECTION_LOST
          @engine.connection_lost(conn)
        end
      end


      # Starts a dedicated send pump for one subscriber connection.
      # Uses write_wire (pre-encoded bytes) for non-encrypted TCP connections
      # to avoid re-encoding the same message N times during fan-out.
      # In conflate mode, drains the batch and keeps only the latest
      # message per topic before writing.
      #
      # @param conn [Connection]
      # @param q [Async::LimitedQueue, DropQueue]
      #
      def start_conn_send_pump(conn, q)
        use_wire = conn.respond_to?(:write_wire) && !conn.encrypted?
        task     = @conflate ? start_conn_send_pump_conflate(conn, q) : start_conn_send_pump_normal(conn, q, use_wire)
        @conn_send_tasks[conn] = task
        @tasks << task
      end


      def start_conn_send_pump_normal(conn, q, use_wire)
        @engine.spawn_pump_task(annotation: "send pump") do
          loop do
            batch = [q.dequeue]
            Routing.drain_send_queue(q, batch)
            if write_matching_batch(conn, batch, use_wire)
              conn.flush
              batch.each { |parts| @engine.emit_verbose_monitor_event(:message_sent, parts: parts) }
            end
          rescue Protocol::ZMTP::Error, *CONNECTION_LOST
            @engine.connection_lost(conn)
            break
          end
        end
      end


      def write_matching_batch(conn, batch, use_wire)
        sent = false
        batch.each do |parts|
          next unless subscribed?(conn, parts.first || EMPTY_BINARY)
          use_wire ? conn.write_wire(Protocol::ZMTP::Codec::Frame.encode_message(parts)) : conn.write_message(parts)
          sent = true
        end
        sent
      end


      def start_conn_send_pump_conflate(conn, q)
        @engine.spawn_pump_task(annotation: "send pump") do
          loop do
            batch = [q.dequeue]
            Routing.drain_send_queue(q, batch)
            # Keep only the latest message that matches the subscription.
            latest = batch.reverse.find { |parts| subscribed?(conn, parts.first || EMPTY_BINARY) }
            next unless latest
            begin
              conn.write_message(latest)
              conn.flush
              @engine.emit_verbose_monitor_event(:message_sent, parts: latest)
            rescue Protocol::ZMTP::Error, *CONNECTION_LOST
              @engine.connection_lost(conn)
              break
            end
          end
        end
      end
    end
  end
end
