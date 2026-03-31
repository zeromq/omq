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


      # @return [Routing] routing strategy
      #
      attr_reader :routing


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
        @closing              = false
        @last_endpoint        = nil
        @last_tcp_port        = nil
        @peer_connected       = Async::Promise.new
        @all_peers_gone       = Async::Promise.new
        @reconnect_enabled    = true
        @parent_task          = nil
        @connection_promises  = {} # connection => Async::Promise
        @fatal_error          = nil
      end


      attr_reader :peer_connected, :all_peers_gone, :connections, :parent_task


      attr_writer :reconnect_enabled


      # Binds to an endpoint.
      #
      # @param endpoint [String] e.g. "tcp://127.0.0.1:5555", "inproc://foo"
      # @return [void]
      # @raise [ArgumentError] on unsupported transport
      #
      def bind(endpoint)
        capture_parent_task
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
        capture_parent_task
        validate_endpoint!(endpoint)
        @connected_endpoints << endpoint
        if endpoint.start_with?("inproc://")
          # Inproc connect is synchronous and instant
          transport = transport_for(endpoint)
          transport.connect(endpoint, self)
        else
          # TCP/IPC connect in background — never blocks the caller
          schedule_reconnect(endpoint, delay: 0)
        end
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
        spawn_connection(io, as_server: true, endpoint: endpoint)
      end


      # Called by a transport when an outgoing connection is established.
      #
      # @param io [#read, #write, #close]
      # @return [void]
      #
      def handle_connected(io, endpoint: nil)
        spawn_connection(io, as_server: false, endpoint: endpoint)
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
        @peer_connected.resolve(pipe)
      end


      # Dequeues the next received message. Blocks until available.
      #
      # @return [Array<String>] message parts
      # @raise if a background pump task crashed
      #
      def dequeue_recv
        raise @fatal_error if @fatal_error
        msg = @routing.recv_queue.dequeue
        raise @fatal_error if msg.nil? && @fatal_error
        msg
      end


      # Pushes a nil sentinel into the recv queue, unblocking a
      # pending {#dequeue_recv} with a nil return value.
      #
      def dequeue_recv_sentinel
        @routing.recv_queue.push(nil)
      end


      # Enqueues a message for sending. Blocks at HWM.
      #
      # @param parts [Array<String>]
      # @return [void]
      # @raise if a background pump task crashed
      #
      def enqueue_send(parts)
        raise @fatal_error if @fatal_error
        @routing.enqueue(parts)
      end


      # Starts a recv pump for a connection, or wires the inproc
      # fast path when the connection is a DirectPipe.
      #
      # @param conn [Connection, Transport::Inproc::DirectPipe]
      # Starts a recv pump that dequeues messages from a connection
      # and enqueues them into the routing strategy's recv queue.
      #
      # When a block is given, each message is yielded for transformation
      # before enqueueing. The block is compiled at the call site, giving
      # YJIT a monomorphic call per routing strategy instead of a shared
      # megamorphic `transform.call` dispatch.
      #
      # @param conn [Connection, Transport::Inproc::DirectPipe]
      # @param recv_queue [Async::LimitedQueue] routing strategy's recv queue
      # @yield [msg] optional per-message transform
      # @return [#stop, nil] pump task handle, or nil for DirectPipe bypass
      #
      def start_recv_pump(conn, recv_queue, &transform)
        if conn.is_a?(Transport::Inproc::DirectPipe) && conn.peer
          conn.peer.direct_recv_queue = recv_queue
          conn.peer.direct_recv_transform = transform
          return nil
        end

        if transform
          Reactor.spawn_pump(annotation: "recv pump") do
            loop do
              msg = conn.receive_message
              msg = transform.call(msg).freeze
              recv_queue.enqueue(msg)
            end
          rescue Async::Stop
          rescue ProtocolError, *CONNECTION_LOST
            connection_lost(conn)
          rescue => error
            signal_fatal_error(error)
          end
        else
          Reactor.spawn_pump(annotation: "recv pump") do
            loop do
              recv_queue.enqueue(conn.receive_message)
            end
          rescue Async::Stop
          rescue ProtocolError, *CONNECTION_LOST
            connection_lost(conn)
          rescue => error
            signal_fatal_error(error)
          end
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

        # Signal the connection task to exit.
        done = @connection_promises.delete(connection)
        done&.resolve(true)

        # Resolve all_peers_gone once: had peers, now have none.
        if @peer_connected.resolved? && @connections.empty?
          @all_peers_gone.resolve(true)
        end

        # Auto-reconnect if this was a connected (not bound) endpoint
        if endpoint && @connected_endpoints.include?(endpoint) && !@closed && !@closing && @reconnect_enabled
          schedule_reconnect(endpoint)
        end
      end


      # Closes all connections and listeners.
      #
      # @return [void]
      #
      def close
        return if @closed || @closing
        @closing = true

        # Stop accepting new connections — but only if we already have
        # peers to drain to. With zero connections the listeners must
        # stay open so late-arriving peers can still receive queued
        # messages during the linger period.
        unless @connections.empty?
          @listeners.each(&:stop)
          @listeners.clear
        end

        # Linger: wait for send queues to drain before closing.
        # linger=0 → close immediately, linger=nil → wait forever.
        # @closed is set AFTER draining so reconnect tasks keep
        # running during the linger period.
        linger = @options.linger
        if linger.nil? || linger > 0
          drain_timeout = linger # nil = wait forever, >0 = seconds
          drain_send_queues(drain_timeout)
        end

        @closed = true

        # Stop any remaining listeners.
        @listeners.each(&:stop)
        @listeners.clear

        # Close connections — causes pump tasks to get EOFError/IOError
        @connections.each(&:close)
        @connections.clear
        # Stop any remaining pump tasks
        @routing.stop rescue nil
        @tasks.each { |t| t.stop rescue nil }
        @tasks.clear
      end


      # Spawns a transient pump task with error propagation.
      #
      # Unexpected exceptions are caught and forwarded to
      # {#signal_fatal_error} so blocked callers (send/recv)
      # see the real error instead of deadlocking.
      #
      # @param annotation [String] task annotation for debugging
      # @yield the pump loop body
      # @return [Async::Task]
      #
      def spawn_pump_task(annotation:, &block)
        @parent_task.async(transient: true, annotation: annotation) do
          yield
        rescue Async::Stop, ProtocolError, *CONNECTION_LOST
          # normal shutdown / expected disconnect
        rescue => error
          signal_fatal_error(error)
        end
      end


      # Wraps an unexpected pump error as {OMQ::SocketDeadError} and
      # unblocks any callers waiting on the recv queue.
      #
      # Must be called from inside a rescue block so that +error+ is
      # +$!+ and Ruby sets it as +#cause+ on the new exception.
      #
      # @param error [Exception]
      #
      def signal_fatal_error(error)
        return if @closing || @closed
        @fatal_error = begin
          raise OMQ::SocketDeadError, "internal error killed #{@socket_type} socket"
        rescue => wrapped
          wrapped
        end
        @routing.recv_queue.enqueue(nil) rescue nil
        @peer_connected.resolve(nil) rescue nil
      end


      private


      # Saves the current Async task so connection subtrees can be
      # spawned as siblings of the caller's task.
      #
      def capture_parent_task
        @parent_task ||= Async::Task.current? ? Async::Task.current : nil
      end


      # Spawns an isolated connection task as a sibling of accept/reconnect
      # tasks. All per-connection children (heartbeat, recv pump, reaper)
      # live inside this task. When the connection dies, the entire subtree
      # is cleaned up by Async.
      #
      def spawn_connection(io, as_server:, endpoint: nil)
        task = @parent_task&.async(transient: true, annotation: "conn #{endpoint}") do
          done = Async::Promise.new
          setup_connection(io, as_server: as_server, endpoint: endpoint, done: done)
          done.wait
        rescue ProtocolError, *CONNECTION_LOST
          # handshake failed or connection lost — subtree cleaned up
        end
        @tasks << task if task
      end


      # Waits for the send queue to drain.
      #
      # @param timeout [Numeric, nil] max seconds to wait (nil = forever)
      #
      def drain_send_queues(timeout)
        return unless @routing.respond_to?(:send_queue)
        deadline = timeout ? Async::Clock.now + timeout : nil

        until @routing.send_queue.empty? &&
              (!@routing.respond_to?(:send_pump_idle?) || @routing.send_pump_idle?)
          if deadline
            remaining = deadline - Async::Clock.now
            break if remaining <= 0
          end
          sleep 0.001
        end
      end


      # Performs the ZMTP handshake, starts heartbeating, and registers
      # the new connection with the routing strategy.
      #
      # @param io [#read, #write, #close] underlying transport stream
      # @param as_server [Boolean] whether we are the ZMTP server side
      # @param endpoint [String, nil] endpoint for reconnection tracking
      # @param done [Async::Promise, nil] resolved when the connection is lost
      #
      def setup_connection(io, as_server:, endpoint: nil, done: nil)
        conn = Connection.new(
          io,
          socket_type:      @socket_type.to_s,
          identity:         @options.identity,
          as_server:        as_server,
          mechanism:        @options.mechanism&.dup,
          max_message_size: @options.max_message_size,
        )
        conn.handshake!
        start_heartbeat(conn)
        @connections << conn
        @connection_endpoints[conn] = endpoint if endpoint
        @connection_promises[conn]  = done if done
        @routing.connection_added(conn)
        @peer_connected.resolve(conn)
      rescue ProtocolError, *CONNECTION_LOST
        conn&.close
        raise
      end


      # Spawns a heartbeat task for the connection.
      # The connection only tracks timestamps — the engine drives the loop.
      #
      # @param conn [Connection]
      # @return [void]
      #
      def start_heartbeat(conn)
        interval = @options.heartbeat_interval
        return unless interval

        ttl     = @options.heartbeat_ttl || interval
        timeout = @options.heartbeat_timeout || interval
        conn.touch_heartbeat

        @tasks << Reactor.spawn_pump(annotation: "heartbeat") do
          loop do
            sleep interval
            conn.send_command(Codec::Command.ping(ttl: ttl, context: "".b))
            if conn.heartbeat_expired?(timeout)
              conn.close
              break
            end
          end
        rescue *CONNECTION_LOST
          # connection closed
        end
      end


      # Spawns a background task that reconnects to the given endpoint
      # with exponential back-off based on the reconnect_interval option.
      #
      # @param endpoint [String] endpoint to reconnect to
      # @param delay [Numeric, nil] initial delay in seconds (defaults to reconnect_interval)
      #
      def schedule_reconnect(endpoint, delay: nil)
        ri = @options.reconnect_interval
        if ri.is_a?(Range)
          delay   ||= ri.begin
          max_delay = ri.end
        else
          delay   ||= ri
          max_delay = nil
        end

        @tasks << Reactor.spawn_pump(annotation: "reconnect #{endpoint}") do
          loop do
            break if @closed
            sleep delay if delay > 0
            break if @closed
            begin
              transport = transport_for(endpoint)
              transport.connect(endpoint, self)
              break # connected successfully
            rescue *CONNECTION_LOST, *CONNECTION_FAILED, ProtocolError
              delay = [delay * 2, max_delay].min if max_delay
              # After first attempt with delay: 0, use the configured interval
              delay = ri.is_a?(Range) ? ri.begin : ri if delay == 0
            end
          end
        rescue Async::Stop
          # normal shutdown
        rescue => error
          signal_fatal_error(error)
        end
      end


      # Eagerly validates TCP hostnames so resolution errors fail
      # on connect, not silently in the background reconnect loop.
      # Reconnects still re-resolve (DNS may change), and transient
      # resolution failures during reconnect are retried with backoff.
      #
      def validate_endpoint!(endpoint)
        return unless endpoint.start_with?("tcp://")
        host = URI.parse(endpoint.sub("tcp://", "http://")).hostname
        Addrinfo.getaddrinfo(host, nil, nil, :STREAM) if host
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
