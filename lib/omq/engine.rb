# frozen_string_literal: true

require "async"
require_relative "engine/recv_pump"
require_relative "engine/heartbeat"
require_relative "engine/reconnect"
require_relative "engine/connection_setup"
require_relative "engine/maintenance"

module OMQ
  # Per-socket orchestrator.
  #
  # Manages connections, transports, and the routing strategy for one
  # OMQ::Socket instance. Each socket type creates one Engine.
  #
  class Engine
    # Scheme → transport module registry.
    # Plugins add entries via +Engine.transports["scheme"] = MyTransport+.
    #
    @transports = {}

    class << self
      # @return [Hash{String => Module}] registered transports
      attr_reader :transports
    end

    # Per-connection metadata: the endpoint it was established on and an
    # optional Promise resolved when the connection is lost (used by
    # {#spawn_connection} to await connection teardown).
    #
    ConnectionRecord = Data.define(:endpoint, :done)


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
      @socket_type       = socket_type
      @options           = options
      @routing           = Routing.for(socket_type).new(self)
      @connections       = {} # connection => ConnectionRecord
      @dialed            = Set.new # endpoints we called connect() on (reconnect intent)
      @listeners         = []
      @tasks             = []
      @state             = :open
      @last_endpoint     = nil
      @last_tcp_port     = nil
      @peer_connected    = Async::Promise.new
      @all_peers_gone    = Async::Promise.new
      @reconnect_enabled = true
      @parent_task       = nil
      @on_io_thread      = false
      @fatal_error       = nil
      @monitor_queue     = nil
    end


    attr_reader :peer_connected, :all_peers_gone, :connections, :parent_task, :tasks

    attr_writer :reconnect_enabled, :monitor_queue

    def closed? = @state == :closed

    # Optional proc that wraps new connections (e.g. for serialization).
    # Called with the raw connection; must return the (possibly wrapped) connection.
    #
    attr_accessor :connection_wrapper


    # Spawns an inproc reconnect retry task under @parent_task.
    #
    # @param endpoint [String]
    # @yield [interval] the retry loop body
    #
    def spawn_inproc_retry(endpoint)
      ri  = @options.reconnect_interval
      ivl = ri.is_a?(Range) ? ri.begin : ri
      @tasks << @parent_task.async(transient: true, annotation: "inproc reconnect #{endpoint}") do
        yield ivl
      rescue Async::Stop
      end
    end


    # Binds to an endpoint.
    #
    # @param endpoint [String] e.g. "tcp://127.0.0.1:5555", "inproc://foo"
    # @return [void]
    # @raise [ArgumentError] on unsupported transport
    #
    def bind(endpoint)
      freeze_error_lists!
      transport = transport_for(endpoint)
      listener  = transport.bind(endpoint, self)
      start_accept_loops(listener)
      @listeners << listener
      @last_endpoint = listener.endpoint
      @last_tcp_port = listener.respond_to?(:port) ? listener.port : nil
      emit_monitor_event(:listening, endpoint: listener.endpoint)
    rescue => error
      emit_monitor_event(:bind_failed, endpoint: endpoint, detail: { error: error })
      raise
    end


    # Connects to an endpoint.
    #
    # @param endpoint [String]
    # @return [void]
    #
    def connect(endpoint)
      freeze_error_lists!
      validate_endpoint!(endpoint)
      @dialed.add(endpoint)
      if endpoint.start_with?("inproc://")
        # Inproc connect is synchronous and instant
        transport = transport_for(endpoint)
        transport.connect(endpoint, self)
      else
        # TCP/IPC connect in background — never blocks the caller
        emit_monitor_event(:connect_delayed, endpoint: endpoint)
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
      @dialed.delete(endpoint)
      close_connections_at(endpoint)
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
      close_connections_at(endpoint)
    end


    # Called by a transport when an incoming connection is accepted.
    #
    # @param io [#read, #write, #close]
    # @param endpoint [String, nil] the endpoint this was accepted on
    # @return [void]
    #
    def handle_accepted(io, endpoint: nil)
      emit_monitor_event(:accepted, endpoint: endpoint)
      spawn_connection(io, as_server: true, endpoint: endpoint)
    end


    # Called by a transport when an outgoing connection is established.
    #
    # @param io [#read, #write, #close]
    # @return [void]
    #
    def handle_connected(io, endpoint: nil)
      emit_monitor_event(:connected, endpoint: endpoint)
      spawn_connection(io, as_server: false, endpoint: endpoint)
    end


    # Called by inproc transport with a pre-validated DirectPipe.
    # Skips ZMTP handshake — just registers with routing strategy.
    #
    # @param pipe [Transport::Inproc::DirectPipe]
    # @return [void]
    #
    def connection_ready(pipe, endpoint: nil)
      pipe = @connection_wrapper.call(pipe) if @connection_wrapper
      @connections[pipe] = ConnectionRecord.new(endpoint: endpoint, done: nil)
      @routing.connection_added(pipe)
      @peer_connected.resolve(pipe)
      emit_monitor_event(:handshake_succeeded, endpoint: endpoint)
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


    # Dequeues up to +max+ messages. Blocks on the first, then
    # drains non-blocking.
    #
    # @param max [Integer]
    # @return [Array<Array<String>>]
    #
    def dequeue_recv_batch(max)
      raise @fatal_error if @fatal_error
      queue = @routing.recv_queue
      msg   = queue.dequeue
      raise @fatal_error if msg.nil? && @fatal_error
      batch = [msg]
      while batch.size < max
        msg = queue.dequeue(timeout: 0)
        break unless msg
        batch << msg
      end
      batch
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


    # Starts a recv pump for a connection, or wires the inproc fast path.
    #
    # @param conn [Connection, Transport::Inproc::DirectPipe]
    # @param recv_queue [SignalingQueue]
    # @yield [msg] optional per-message transform
    # @return [Async::Task, nil]
    #
    def start_recv_pump(conn, recv_queue, &transform)
      task = RecvPump.start(@parent_task, conn, recv_queue, self, transform)
      @tasks << task if task
      task
    end


    # Called when a connection is lost.
    #
    # @param connection [Connection]
    # @return [void]
    #
    def connection_lost(connection)
      entry = @connections.delete(connection)
      @routing.connection_removed(connection)
      connection.close
      emit_monitor_event(:disconnected, endpoint: entry&.endpoint)
      entry&.done&.resolve(true)
      @all_peers_gone.resolve(true) if @peer_connected.resolved? && @connections.empty?
      maybe_reconnect(entry&.endpoint)
    end


    # Closes all connections and listeners.
    #
    # @return [void]
    #
    def close
      return unless @state == :open
      @state = :closing
      stop_listeners unless @connections.empty?
      drain_send_queues(@options.linger) if @options.linger.nil? || @options.linger > 0
      @state = :closed
      Reactor.untrack_linger(@options.linger) if @on_io_thread
      stop_listeners
      close_connections
      stop_tasks
      emit_monitor_event(:closed)
      close_monitor_queue
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
      rescue Async::Stop, Protocol::ZMTP::Error, *CONNECTION_LOST
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
      return unless @state == :open
      @fatal_error = begin
        raise OMQ::SocketDeadError, "internal error killed #{@socket_type} socket"
      rescue => wrapped
        wrapped
      end
      @routing.recv_queue.push(nil) rescue nil
      @peer_connected.resolve(nil) rescue nil
    end


    # Saves the current Async task so connection subtrees can be
    # spawned under the caller's task tree. Called by Socket before
    # the first bind/connect — outside Reactor.run so non-Async
    # callers get the IO thread's root task, not an ephemeral work task.
    #
    def capture_parent_task
      return if @parent_task
      if Async::Task.current?
        @parent_task = Async::Task.current
      else
        @parent_task  = Reactor.root_task
        @on_io_thread = true
        Reactor.track_linger(@options.linger)
      end
      Maintenance.start(@parent_task, @options.mechanism, @tasks)
    end


    def emit_monitor_event(type, endpoint: nil, detail: nil)
      return unless @monitor_queue
      @monitor_queue.push(MonitorEvent.new(type: type, endpoint: endpoint, detail: detail))
    rescue Async::Stop, ClosedQueueError
    end

    def transport_for(endpoint)
      scheme = endpoint[/\A([^:]+):\/\//, 1]
      self.class.transports[scheme] or
        raise ArgumentError, "unsupported transport: #{endpoint}"
    end

    private

    def spawn_connection(io, as_server:, endpoint: nil)
      task = @parent_task&.async(transient: true, annotation: "conn #{endpoint}") do
        done = Async::Promise.new
        conn = ConnectionSetup.run(io, self, as_server: as_server, endpoint: endpoint, done: done)
        done.wait
      rescue Protocol::ZMTP::Error, *CONNECTION_LOST
        # handshake failed or connection lost — subtree cleaned up
      ensure
        conn&.close rescue nil
      end
      @tasks << task if task
    end

    def drain_send_queues(timeout)
      return unless @routing.respond_to?(:send_queues_drained?)
      deadline = timeout ? Async::Clock.now + timeout : nil
      until @routing.send_queues_drained?
        break if deadline && (deadline - Async::Clock.now) <= 0
        sleep 0.001
      end
    end

    def maybe_reconnect(endpoint)
      return unless endpoint && @dialed.include?(endpoint)
      return unless @state == :open && @reconnect_enabled
      Reconnect.schedule(endpoint, @options, @parent_task, self)
    end

    def schedule_reconnect(endpoint, delay: nil)
      Reconnect.schedule(endpoint, @options, @parent_task, self, delay: delay)
    end

    def validate_endpoint!(endpoint)
      transport = transport_for(endpoint)
      transport.validate_endpoint!(endpoint) if transport.respond_to?(:validate_endpoint!)
    end

    def start_accept_loops(listener)
      return unless listener.respond_to?(:start_accept_loops)
      listener.start_accept_loops(@parent_task) do |io|
        handle_accepted(io, endpoint: listener.endpoint)
      end
    end

    def stop_listeners
      @listeners.each(&:stop)
      @listeners.clear
    end

    def close_connections
      @connections.each_key(&:close)
      @connections.clear
    end

    def close_connections_at(endpoint)
      conns = @connections.filter_map { |conn, e| conn if e.endpoint == endpoint }
      conns.each do |conn|
        @connections.delete(conn)
        @routing.connection_removed(conn)
        conn.close
      end
    end

    def stop_tasks
      @routing.stop rescue nil
      @tasks.each { |t| t.stop rescue nil }
      @tasks.clear
    end

    def freeze_error_lists!
      return if OMQ::CONNECTION_LOST.frozen?
      OMQ::CONNECTION_LOST.freeze
      OMQ::CONNECTION_FAILED.freeze
    end

    def close_monitor_queue
      return unless @monitor_queue
      @monitor_queue.push(nil)
    end
  end

  # Register built-in transports.
  Engine.transports["tcp"]    = Transport::TCP
  Engine.transports["ipc"]    = Transport::IPC
  Engine.transports["inproc"] = Transport::Inproc
end
