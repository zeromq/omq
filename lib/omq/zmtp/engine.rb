# frozen_string_literal: true

require "async"

module OMQ
  module ZMTP
    # Per-socket orchestrator.
    #
    # Manages connections, transports, and the routing strategy for one
    # OMQ::Socket instance. Each socket type creates one Engine.
    #
    class Engine
      # @return [Symbol] socket type (e.g. :REQ, :PAIR)
      #
      attr_reader :socket_type

      # @return [Options] socket options
      #
      attr_reader :options

      # @return [String, nil] last bound endpoint
      #
      attr_reader :last_endpoint

      # @return [Integer, nil] last auto-selected TCP port
      #
      attr_reader :last_tcp_port

      # @param socket_type [Symbol] e.g. :REQ, :REP, :PAIR
      # @param options [Options]
      #
      def initialize(socket_type, options)
        @socket_type          = socket_type
        @options              = options
        @routing              = Routing.for(socket_type).new(self)
        @connections          = []
        @connection_endpoints = {} # connection => endpoint (for reconnection)
        @connected_endpoints  = [] # endpoints we connected to (not bound)
        @listeners            = []
        @tasks                = []
        @closed               = false
        @last_endpoint        = nil
        @last_tcp_port        = nil
      end

      # Binds to an endpoint.
      #
      # @param endpoint [String] e.g. "tcp://127.0.0.1:5555", "inproc://foo"
      # @return [void]
      # @raise [ArgumentError] on unsupported transport
      #
      def bind(endpoint)
        transport = transport_for(endpoint)
        listener = transport.bind(endpoint, self)
        @listeners << listener
        @last_endpoint = listener.endpoint
        @last_tcp_port = extract_tcp_port(listener.endpoint)
      end

      # Connects to an endpoint.
      #
      # @param endpoint [String]
      # @return [void]
      #
      def connect(endpoint)
        @connected_endpoints << endpoint
        transport = transport_for(endpoint)
        transport.connect(endpoint, self)
      end

      # Disconnects from an endpoint. Closes connections to that endpoint
      # and stops auto-reconnection for it.
      #
      # @param endpoint [String]
      # @return [void]
      #
      def disconnect(endpoint)
        @connected_endpoints.delete(endpoint)
        conns = @connection_endpoints.select { |_, ep| ep == endpoint }.keys
        conns.each do |conn|
          @connection_endpoints.delete(conn)
          @connections.delete(conn)
          @routing.connection_removed(conn)
          conn.close
        end
      end

      # Unbinds from an endpoint. Stops the listener and closes all
      # connections that were accepted on it.
      #
      # @param endpoint [String]
      # @return [void]
      #
      def unbind(endpoint)
        listener = @listeners.find { |l| l.endpoint == endpoint }
        return unless listener
        listener.stop
        @listeners.delete(listener)

        # Close connections accepted on this endpoint
        conns = @connection_endpoints.select { |_, ep| ep == endpoint }.keys
        conns.each do |conn|
          @connection_endpoints.delete(conn)
          @connections.delete(conn)
          @routing.connection_removed(conn)
          conn.close
        end
      end

      # Called by a transport when an incoming connection is accepted.
      #
      # @param io [#read, #write, #close]
      # @param endpoint [String, nil] the endpoint this was accepted on
      # @return [void]
      #
      def handle_accepted(io, endpoint: nil)
        setup_connection(io, as_server: true, endpoint: endpoint)
      end

      # Called by a transport when an outgoing connection is established.
      #
      # @param io [#read, #write, #close]
      # @return [void]
      #
      def handle_connected(io, endpoint: nil)
        setup_connection(io, as_server: false, endpoint: endpoint)
      end

      # Called by inproc transport with a pre-validated DirectPipe.
      # Skips ZMTP handshake — just registers with routing strategy.
      #
      # @param pipe [Transport::Inproc::DirectPipe]
      # @return [void]
      #
      def connection_ready(pipe, endpoint: nil)
        @connections << pipe
        @connection_endpoints[pipe] = endpoint if endpoint
        @routing.connection_added(pipe)
      end

      # Dequeues the next received message. Blocks until available.
      #
      # @return [Array<String>] message parts
      #
      def dequeue_recv
        @routing.recv_queue.dequeue
      end

      # Enqueues a message for sending. Blocks at HWM.
      #
      # @param parts [Array<String>]
      # @return [void]
      #
      def enqueue_send(parts)
        @routing.enqueue(parts)
      end

      # Starts a recv pump for a connection, or wires the inproc
      # fast path when the connection is a DirectPipe.
      #
      # @param conn [Connection, Transport::Inproc::DirectPipe]
      # @param recv_queue [Async::LimitedQueue] routing strategy's recv queue
      # @param transform [#call, nil] optional message transform
      # @return [#stop, nil] pump task handle, or nil for DirectPipe bypass
      #
      def start_recv_pump(conn, recv_queue, transform: nil)
        if conn.is_a?(Transport::Inproc::DirectPipe) && conn.peer
          conn.peer.direct_recv_queue = recv_queue
          conn.peer.direct_recv_transform = transform
          return nil
        end

        Reactor.spawn_pump do
          loop do
            msg = conn.receive_message
            msg = transform ? transform.call(msg) : msg
            recv_queue.enqueue(msg)
          end
        rescue EOFError, IOError
          connection_lost(conn)
        end
      end

      # Called when a connection is lost.
      #
      # @param connection [Connection]
      # @return [void]
      #
      def connection_lost(connection)
        endpoint = @connection_endpoints.delete(connection)
        @connections.delete(connection)
        @routing.connection_removed(connection)
        connection.close

        # Auto-reconnect if this was a connected (not bound) endpoint
        if endpoint && @connected_endpoints.include?(endpoint) && !@closed
          schedule_reconnect(endpoint)
        end
      end

      # Closes all connections and listeners.
      #
      # @return [void]
      #
      def close
        return if @closed
        @closed = true

        # Linger: wait for send queues to drain before closing.
        # linger=0 → close immediately, linger=nil → wait forever.
        linger = @options.linger
        if linger.nil? || linger > 0
          drain_timeout = linger # nil = wait forever, >0 = seconds
          drain_send_queues(drain_timeout)
        end

        # Close connections — causes pump tasks to get EOFError/IOError
        @connections.each(&:close)
        @connections.clear
        @listeners.each(&:stop)
        @listeners.clear
        # Stop any remaining pump tasks
        @routing.stop rescue nil
        @tasks.each { |t| t.stop rescue nil }
        @tasks.clear
      end

      private

      # Waits for the send queue to drain.
      #
      # @param timeout [Numeric, nil] max seconds to wait (nil = forever)
      #
      def drain_send_queues(timeout)
        return unless @routing.respond_to?(:send_queue)
        deadline = timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout : nil

        until @routing.send_queue.empty?
          if deadline
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if remaining <= 0
          end
          sleep 0.001
        end
      end

      def setup_connection(io, as_server:, endpoint: nil)
        conn = Connection.new(
          io,
          socket_type:       @socket_type.to_s,
          identity:          @options.identity,
          as_server:         as_server,
          heartbeat_interval: @options.heartbeat_interval,
          heartbeat_ttl:      @options.heartbeat_ttl,
          heartbeat_timeout:  @options.heartbeat_timeout,
          max_message_size:   @options.max_message_size,
        )
        conn.handshake!
        conn.start_heartbeat
        @connections << conn
        @connection_endpoints[conn] = endpoint if endpoint
        @routing.connection_added(conn)
      rescue ProtocolError, EOFError
        conn&.close
        raise
      end

      def schedule_reconnect(endpoint)
        ri = @options.reconnect_interval
        if ri.is_a?(Range)
          delay   = ri.begin
          max_delay = ri.end
        else
          delay     = ri
          max_delay = nil
        end

        @tasks << Reactor.spawn_pump do
          loop do
            break if @closed
            sleep delay
            break if @closed
            begin
              transport = transport_for(endpoint)
              transport.connect(endpoint, self)
              break # reconnected successfully
            rescue Errno::ECONNREFUSED, IOError, ProtocolError
              delay = [delay * 2, max_delay].min if max_delay
            end
          end
        end
      end


      def transport_for(endpoint)
        case endpoint
        when /\Atcp:\/\//    then Transport::TCP
        when /\Aipc:\/\//    then Transport::IPC
        when /\Ainproc:\/\// then Transport::Inproc
        else raise ArgumentError, "unsupported transport: #{endpoint}"
        end
      end

      def extract_tcp_port(endpoint)
        return nil unless endpoint&.start_with?("tcp://")
        port = endpoint.split(":").last.to_i
        port.positive? ? port : nil
      end
    end
  end
end
