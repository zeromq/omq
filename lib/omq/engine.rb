# frozen_string_literal: true

require "async"
require_relative "engine/recv_pump"
require_relative "engine/heartbeat"
require_relative "engine/reconnect"
require_relative "engine/connection_lifecycle"
require_relative "engine/socket_lifecycle"
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


    # @return [Symbol] socket type (e.g. :REQ, :PAIR)
    #
    attr_reader :socket_type


    # @return [Options] socket options
    #
    attr_reader :options


    # @return [Routing] routing strategy (created lazily on first access)
    #
    def routing
      @routing ||= Routing.for(@socket_type).new(self)
    end


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
      @socket_type     = socket_type
      @options         = options
      @routing         = nil
      @connections     = {} # connection => ConnectionLifecycle
      @dialed          = Set.new # endpoints we called connect() on (reconnect intent)
      @listeners       = []
      @tasks           = []
      @lifecycle       = SocketLifecycle.new
      @last_endpoint   = nil
      @last_tcp_port   = nil
      @fatal_error     = nil
      @monitor_queue   = nil
      @verbose_monitor = false
    end


    # @return [Hash{Connection => ConnectionLifecycle}] active connections
    # @return [Array<Async::Task>] background tasks (pumps, heartbeat, reconnect)
    # @return [SocketLifecycle] socket-level state + signaling
    #
    attr_reader :connections, :tasks, :lifecycle

    # @!attribute [w] monitor_queue
    #   @param value [Async::Queue, nil] queue for monitor events
    #
    attr_writer :monitor_queue
    attr_accessor :verbose_monitor


    # Delegated to {SocketLifecycle}.
    def peer_connected    = @lifecycle.peer_connected
    def all_peers_gone    = @lifecycle.all_peers_gone
    def parent_task       = @lifecycle.parent_task
    def closed?           = @lifecycle.closed?
    def reconnect_enabled=(value)
      @lifecycle.reconnect_enabled = value
    end

    # Optional proc that wraps new connections (e.g. for serialization).
    # Called with the raw connection; must return the (possibly wrapped) connection.
    #
    attr_accessor :connection_wrapper


    # Spawns an inproc reconnect retry task under the socket's parent task.
    #
    # @param endpoint [String]
    # @yield [interval] the retry loop body
    #
    def spawn_inproc_retry(endpoint)
      ri  = @options.reconnect_interval
      ivl = ri.is_a?(Range) ? ri.begin : ri
      @tasks << @lifecycle.parent_task.async(transient: true, annotation: "inproc reconnect #{endpoint}") do
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
      OMQ.freeze_for_ractors!
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
      OMQ.freeze_for_ractors!
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
      ConnectionLifecycle.new(self, endpoint: endpoint).ready_direct!(pipe)
    end


    # Dequeues the next received message. Blocks until available.
    #
    # @return [Array<String>] message parts
    # @raise if a background pump task crashed
    #
    def dequeue_recv
      raise @fatal_error if @fatal_error
      msg = routing.recv_queue.dequeue
      raise @fatal_error if msg.nil? && @fatal_error
      msg
    end


    # Dequeues up to +max+ messages or +max_bytes+ total. Blocks
    # on the first, then drains non-blocking.
    #
    # @param max [Integer] message count limit
    # @param max_bytes [Integer] byte size limit
    # @return [Array<Array<String>>]
    #
    def dequeue_recv_batch(max, max_bytes: 1 << 20)
      raise @fatal_error if @fatal_error
      queue = routing.recv_queue
      msg   = queue.dequeue
      raise @fatal_error if msg.nil? && @fatal_error
      batch = [msg]
      bytes = msg.sum(&:bytesize)
      while batch.size < max && bytes < max_bytes
        msg = queue.dequeue(timeout: 0)
        break unless msg
        batch << msg
        bytes += msg.sum(&:bytesize)
      end
      batch
    end


    # Pushes a nil sentinel into the recv queue, unblocking a
    # pending {#dequeue_recv} with a nil return value.
    #
    def dequeue_recv_sentinel
      routing.recv_queue.push(nil)
    end


    # Enqueues a message for sending. Blocks at HWM.
    #
    # @param parts [Array<String>]
    # @return [void]
    # @raise if a background pump task crashed
    #
    def enqueue_send(parts)
      raise @fatal_error if @fatal_error
      routing.enqueue(parts)
    end


    # Starts a recv pump for a connection, or wires the inproc fast path.
    #
    # @param conn [Connection, Transport::Inproc::DirectPipe]
    # @param recv_queue [SignalingQueue]
    # @yield [msg] optional per-message transform
    # @return [Async::Task, nil]
    #
    def start_recv_pump(conn, recv_queue, &transform)
      task = RecvPump.start(Async::Task.current, conn, recv_queue, self, transform)
      @tasks << task if task
      task
    end


    # Called when a connection is lost.
    #
    # @param connection [Connection]
    # @return [void]
    #
    def connection_lost(connection)
      @connections[connection]&.lost!
    end


    # Resolves `all_peers_gone` if we had peers and now have none.
    # Called by ConnectionLifecycle during teardown.
    #
    def resolve_all_peers_gone_if_empty
      @lifecycle.resolve_all_peers_gone_if_empty(@connections)
    end


    # Schedules a reconnect for +endpoint+ if auto-reconnect is enabled
    # and the endpoint is still dialed.
    #
    def maybe_reconnect(endpoint)
      return unless endpoint && @dialed.include?(endpoint)
      return unless @lifecycle.open? && @lifecycle.reconnect_enabled
      Reconnect.schedule(endpoint, @options, @lifecycle.parent_task, self)
    end


    # Closes all connections and listeners.
    #
    # @return [void]
    #
    def close
      return unless @lifecycle.open?
      @lifecycle.start_closing!
      stop_listeners unless @connections.empty?
      drain_send_queues(@options.linger) if @options.linger.nil? || @options.linger > 0
      @lifecycle.finish_closing!
      Reactor.untrack_linger(@options.linger) if @lifecycle.on_io_thread
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
      Async::Task.current.async(transient: true, annotation: annotation) do
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
      return unless @lifecycle.open?
      @fatal_error = begin
        raise OMQ::SocketDeadError, "internal error killed #{@socket_type} socket"
      rescue => wrapped
        wrapped
      end
      routing.recv_queue.push(nil) rescue nil
      @lifecycle.peer_connected.resolve(nil) rescue nil
    end


    # Saves the current Async task so connection subtrees can be
    # spawned under the caller's task tree. Called by Socket before
    # the first bind/connect — outside Reactor.run so non-Async
    # callers get the IO thread's root task, not an ephemeral work task.
    #
    def capture_parent_task
      return unless @lifecycle.capture_parent_task(linger: @options.linger)
      Maintenance.start(@lifecycle.parent_task, @options.mechanism, @tasks)
    end


    # Emits a lifecycle event to the monitor queue, if one is attached.
    #
    # @param type [Symbol] event type (e.g. :listening, :connected, :disconnected)
    # @param endpoint [String, nil] the endpoint involved
    # @param detail [Hash, nil] extra context
    # @return [void]
    #
    def emit_monitor_event(type, endpoint: nil, detail: nil)
      return unless @monitor_queue
      @monitor_queue.push(MonitorEvent.new(type: type, endpoint: endpoint, detail: detail))
    rescue Async::Stop, ClosedQueueError
    end


    # Emits a verbose-only monitor event (e.g. message traces).
    # Only emitted when {Socket#monitor} was called with +verbose: true+.
    # Uses +**detail+ to avoid Hash allocation when verbose is off.
    #
    # @param type [Symbol] event type (e.g. :message_sent, :message_received)
    # @param detail [Hash] extra context forwarded as keyword args
    # @return [void]
    #
    def emit_verbose_monitor_event(type, **detail)
      return unless @verbose_monitor
      emit_monitor_event(type, detail: detail)
    end


    # Looks up the transport module for an endpoint URI.
    #
    # @param endpoint [String] endpoint URI (e.g. "tcp://...", "inproc://...")
    # @return [Module] the transport module
    # @raise [ArgumentError] if the scheme is not registered
    #
    def transport_for(endpoint)
      scheme = endpoint[/\A([^:]+):\/\//, 1]
      self.class.transports[scheme] or
        raise ArgumentError, "unsupported transport: #{endpoint}"
    end

    private

    def spawn_connection(io, as_server:, endpoint: nil)
      task = @lifecycle.parent_task&.async(transient: true, annotation: "conn #{endpoint}") do
        done      = Async::Promise.new
        lifecycle = ConnectionLifecycle.new(self, endpoint: endpoint, done: done)
        lifecycle.handshake!(io, as_server: as_server)
        done.wait
      rescue Async::Queue::ClosedError
        # connection dropped during drain — message re-staged
      rescue Protocol::ZMTP::Error, *CONNECTION_LOST
        # handshake failed or connection lost — subtree cleaned up
      ensure
        lifecycle&.close!
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


    def schedule_reconnect(endpoint, delay: nil)
      Reconnect.schedule(endpoint, @options, @lifecycle.parent_task, self, delay: delay)
    end


    def validate_endpoint!(endpoint)
      transport = transport_for(endpoint)
      transport.validate_endpoint!(endpoint) if transport.respond_to?(:validate_endpoint!)
    end


    def start_accept_loops(listener)
      return unless listener.respond_to?(:start_accept_loops)
      listener.start_accept_loops(@lifecycle.parent_task) do |io|
        handle_accepted(io, endpoint: listener.endpoint)
      end
    end


    def stop_listeners
      @listeners.each(&:stop)
      @listeners.clear
    end


    def close_connections
      @connections.values.each(&:close!)
    end


    def close_connections_at(endpoint)
      @connections.values.select { |lc| lc.endpoint == endpoint }.each(&:close!)
    end


    def stop_tasks
      routing.stop rescue nil
      @tasks.each { |t| t.stop rescue nil }
      @tasks.clear
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
