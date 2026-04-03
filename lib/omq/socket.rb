# frozen_string_literal: true

require "forwardable"

module OMQ
  # Socket base class.
  #
  class Socket
    # @return [Options]
    #
    attr_reader :options


    # @return [Integer, nil] last auto-selected TCP port
    #
    attr_reader :last_tcp_port


    # Delegate socket option accessors to @options.
    #
    extend Forwardable

    def_delegators :@options,
      :send_hwm,              :send_hwm=,
      :recv_hwm,              :recv_hwm=,
      :linger,                :linger=,
      :identity,              :identity=,
      :recv_timeout,          :recv_timeout=,
      :send_timeout,          :send_timeout=,
      :read_timeout,          :read_timeout=,
      :write_timeout,         :write_timeout=,
      :router_mandatory,      :router_mandatory=,
      :router_mandatory?,
      :reconnect_interval,    :reconnect_interval=,
      :heartbeat_interval,    :heartbeat_interval=,
      :heartbeat_ttl,         :heartbeat_ttl=,
      :heartbeat_timeout,     :heartbeat_timeout=,
      :max_message_size,      :max_message_size=,
      :mechanism,             :mechanism=,
      :tls_context,           :tls_context=


    # Creates a new socket and binds it to the given endpoint.
    #
    # @param endpoint [String]
    # @param opts [Hash] keyword arguments forwarded to {#initialize}
    # @return [Socket]
    #
    def self.bind(endpoint, **opts)
      new(nil, **opts).tap { |s| s.bind(endpoint) }
    end


    # Creates a new socket and connects it to the given endpoint.
    #
    # @param endpoint [String]
    # @param opts [Hash] keyword arguments forwarded to {#initialize}
    # @return [Socket]
    #
    def self.connect(endpoint, **opts)
      new(nil, **opts).tap { |s| s.connect(endpoint) }
    end


    def initialize(endpoints = nil, linger: 0); end


    # Binds to an endpoint.
    #
    # @param endpoint [String]
    # @return [void]
    #
    def bind(endpoint)
      ensure_parent_task
      Reactor.run do
        @engine.bind(endpoint)
        @last_tcp_port = @engine.last_tcp_port
      end
    end


    # Connects to an endpoint.
    #
    # @param endpoint [String]
    # @return [void]
    #
    def connect(endpoint)
      ensure_parent_task
      Reactor.run { @engine.connect(endpoint) }
    end


    # Disconnects from an endpoint.
    #
    # @param endpoint [String]
    # @return [void]
    #
    def disconnect(endpoint)
      Reactor.run { @engine.disconnect(endpoint) }
    end


    # Unbinds from an endpoint.
    #
    # @param endpoint [String]
    # @return [void]
    #
    def unbind(endpoint)
      Reactor.run { @engine.unbind(endpoint) }
    end


    # @return [String, nil] last bound endpoint
    #
    def last_endpoint
      @engine.last_endpoint
    end


    # @return [Async::Promise] resolves when first peer completes handshake
    def peer_connected   = @engine.peer_connected


    # @return [Async::Promise] resolves when first subscriber joins (PUB/XPUB only)
    def subscriber_joined = @engine.routing.subscriber_joined


    # @return [Async::Promise] resolves when all peers disconnect (after having had peers)
    def all_peers_gone   = @engine.all_peers_gone


    # @return [Integer] current number of peer connections
    def connection_count = @engine.connections.size


    # Signals end-of-stream on the receive side. A subsequent
    # +#receive+ call that would otherwise block returns +nil+.
    #
    def close_read
      @engine.dequeue_recv_sentinel
    end


    # Yields lifecycle events for this socket.
    #
    # Spawns a background fiber that reads from an internal event queue.
    # The block receives {MonitorEvent} instances until the socket is
    # closed or the returned task is stopped.
    #
    # @yield [event] called for each lifecycle event
    # @yieldparam event [MonitorEvent]
    # @return [Async::Task] the monitor task (call +#stop+ to end early)
    #
    # @example
    #   task = socket.monitor do |event|
    #     case event
    #     in type: :connected, endpoint:
    #       puts "peer up: #{endpoint}"
    #     in type: :disconnected, endpoint:
    #       puts "peer down: #{endpoint}"
    #     end
    #   end
    #   # later:
    #   task.stop
    #
    def monitor(&block)
      ensure_parent_task
      queue = Async::Queue.new
      @engine.monitor_queue = queue
      Reactor.run do
        @engine.parent_task.async(transient: true, annotation: "monitor") do
          while (event = queue.dequeue)
            block.call(event)
          end
        rescue Async::Stop
        ensure
          @engine.monitor_queue = nil
          block.call(MonitorEvent.new(type: :monitor_stopped))
        end
      end
    end


    # Disable auto-reconnect for connected endpoints.
    def reconnect_enabled=(val)
      @engine.reconnect_enabled = val
    end


    # Closes the socket.
    #
    def close
      Reactor.run { @engine.close }
      nil
    end


    # Set socket to use unbounded pipes (HWM=0).
    #
    def set_unbounded
      @options.send_hwm = 0
      @options.recv_hwm = 0
      nil
    end


    # @return [String]
    #
    def inspect
      format("#<%s last_endpoint=%p>", self.class, last_endpoint)
    end


    private


    # Runs a block with a timeout. Uses Async's with_timeout if inside
    # a reactor, otherwise falls back to Timeout.timeout.
    #
    # @param seconds [Numeric]
    # @raise [IO::TimeoutError]
    #
    def with_timeout(seconds, &block)
      return yield if seconds.nil?
      if Async::Task.current?
        Async::Task.current.with_timeout(seconds, &block)
      else
        Timeout.timeout(seconds, &block)
      end
    rescue Async::TimeoutError, Timeout::Error
      raise IO::TimeoutError, "timed out"
    end


    # Sets the engine's parent task before the first bind or connect.
    # Must be called OUTSIDE Reactor.run so that non-Async callers
    # get the IO thread's root task, not an ephemeral work task.
    #
    def ensure_parent_task
      @engine.capture_parent_task
    end


    # Connects or binds based on endpoint prefix convention.
    #
    # @param endpoints [String, nil]
    # @param default [Symbol] :connect or :bind
    #
    def _attach(endpoints, default:)
      return unless endpoints
      case endpoints
      when /\A@(.+)\z/
        bind($1)
      when /\A>(.+)\z/
        connect($1)
      else
        __send__(default, endpoints)
      end
    end


    # Initializes engine and options for a socket type.
    #
    # @param socket_type [Symbol]
    # @param linger [Integer]
    #
    def _init_engine(socket_type, linger:, send_hwm: nil, recv_hwm: nil,
                     send_timeout: nil, recv_timeout: nil, conflate: false,
                     backend: nil)
      @options = Options.new(linger: linger)
      @options.send_hwm      = send_hwm     if send_hwm
      @options.recv_hwm      = recv_hwm     if recv_hwm
      @options.send_timeout   = send_timeout if send_timeout
      @options.recv_timeout   = recv_timeout if recv_timeout
      @options.conflate       = conflate
      @recv_buffer = []
      @recv_mutex  = Mutex.new
      @engine      = case backend
                     when nil, :ruby then Engine.new(socket_type, @options)
                     when :ffi       then FFI::Engine.new(socket_type, @options)
                     else raise ArgumentError, "unknown backend: #{backend}"
                     end
    end
  end
end
