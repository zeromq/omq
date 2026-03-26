# frozen_string_literal: true

module OMQ
  # Socket base class.
  #
  class Socket
    # @return [ZMTP::Options]
    #
    attr_reader :options

    # @return [Integer, nil] last auto-selected TCP port
    #
    attr_reader :last_tcp_port

    # Delegate socket option accessors to @options.
    #
    %i[
      send_hwm                send_hwm=
      recv_hwm                recv_hwm=
      linger                  linger=
      identity                identity=
      recv_timeout            recv_timeout=
      send_timeout            send_timeout=
      read_timeout            read_timeout=
      write_timeout           write_timeout=
      router_mandatory        router_mandatory=
      router_mandatory?
      reconnect_interval      reconnect_interval=
      heartbeat_interval      heartbeat_interval=
      heartbeat_ttl           heartbeat_ttl=
      heartbeat_timeout       heartbeat_timeout=
      max_message_size        max_message_size=
      mechanism               mechanism=
      curve_server            curve_server=
      curve_server_key        curve_server_key=
      curve_public_key        curve_public_key=
      curve_secret_key        curve_secret_key=
      curve_authenticator     curve_authenticator=
    ].each do |method|
      define_method(method) { |*args| @options.public_send(method, *args) }
    end

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
      @engine.bind(endpoint)
      @last_tcp_port = @engine.last_tcp_port
    end

    # Connects to an endpoint.
    #
    # @param endpoint [String]
    # @return [void]
    #
    def connect(endpoint)
      @engine.connect(endpoint)
    end

    # Disconnects from an endpoint.
    #
    # @param endpoint [String]
    # @return [void]
    #
    def disconnect(endpoint)
      @engine.disconnect(endpoint)
    end

    # Unbinds from an endpoint.
    #
    # @param endpoint [String]
    # @return [void]
    #
    def unbind(endpoint)
      @engine.unbind(endpoint)
    end

    # @return [String, nil] last bound endpoint
    #
    def last_endpoint
      @engine.last_endpoint
    end

    # Closes the socket.
    #
    # @return [void]
    #
    def close
      @engine.close
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
    def _init_engine(socket_type, linger:)
      @options = ZMTP::Options.new(linger: linger)
      @engine  = ZMTP::Engine.new(socket_type, @options)
    end
  end
end
