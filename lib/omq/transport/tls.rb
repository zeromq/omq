# frozen_string_literal: true

require "socket"
require "uri"
require "openssl"
require "io/stream"

module OMQ
  module Transport
    # TLS transport — TLS v1.3 on top of TCP.
    #
    # Requires the socket's +tls_context+ to be set to an
    # +OpenSSL::SSL::SSLContext+ before bind or connect.
    #
    module TLS
      TLS_PREFIX = "tls+tcp://"

      class << self
        # Binds a TLS server.
        #
        # @param endpoint [String] e.g. "tls+tcp://127.0.0.1:5555" or "tls+tcp://*:0"
        # @param engine [Engine]
        # @return [Listener]
        #
        def bind(endpoint, engine)
          ctx = require_context!(engine)
          host, port = parse_endpoint(endpoint)
          host = "0.0.0.0" if host == "*"

          addrs = Addrinfo.getaddrinfo(host, port, nil, :STREAM, nil, ::Socket::AI_PASSIVE)
          raise ::Socket::ResolutionError, "no addresses for #{host}" if addrs.empty?

          servers     = []
          actual_port = nil

          addrs.each do |addr|
            server = TCPServer.new(addr.ip_address, actual_port || port)
            actual_port ||= server.local_address.ip_port
            servers << server
          end

          host_part = host.include?(":") ? "[#{host}]" : host
          resolved  = "#{TLS_PREFIX}#{host_part}:#{actual_port}"
          Listener.new(resolved, servers, actual_port, ctx)
        end

        # Connects to a TLS endpoint.
        #
        # @param endpoint [String] e.g. "tls+tcp://127.0.0.1:5555"
        # @param engine [Engine]
        # @return [void]
        #
        def connect(endpoint, engine)
          ctx = require_context!(engine)
          host, port = parse_endpoint(endpoint)
          tcp_sock   = TCPSocket.new(host, port)

          ssl            = OpenSSL::SSL::SSLSocket.new(tcp_sock, ctx)
          ssl.sync_close = true
          ssl.hostname   = host
          ssl.connect

          engine.handle_connected(IO::Stream::Buffered.wrap(ssl), endpoint: endpoint)
        rescue
          tcp_sock&.close unless ssl&.sync_close
          raise
        end

        private

        # Validates and freezes the TLS context from engine options.
        #
        # The context SHOULD have min_version set to TLS1_3_VERSION.
        # We cannot validate this because SSLContext#min_version is
        # write-only in Ruby's OpenSSL binding.
        #
        # @return [OpenSSL::SSL::SSLContext]
        # @raise [ArgumentError] if no context is set
        #
        def require_context!(engine)
          ctx = engine.options.tls_context
          raise ArgumentError, "tls_context must be set for tls+tcp:// endpoints" unless ctx
          ctx.freeze unless ctx.frozen?
          ctx
        end

        # Parses a tls+tcp:// endpoint URI into host and port.
        #
        # @param endpoint [String]
        # @return [Array(String, Integer)]
        #
        def parse_endpoint(endpoint)
          uri = URI.parse("http://#{endpoint.delete_prefix(TLS_PREFIX)}")
          [uri.hostname, uri.port]
        end
      end

      # A bound TLS listener.
      #
      class Listener
        # @return [String] resolved endpoint with actual port
        attr_reader :endpoint

        # @return [Integer] bound port
        attr_reader :port

        # @return [Array<TCPServer>] bound server sockets
        attr_reader :servers

        # @return [OpenSSL::SSL::SSLContext]
        attr_reader :ssl_context


        # @param endpoint [String] resolved endpoint URI
        # @param servers [Array<TCPServer>]
        # @param port [Integer] bound port number
        # @param ssl_context [OpenSSL::SSL::SSLContext]
        #
        def initialize(endpoint, servers, port, ssl_context)
          @endpoint    = endpoint
          @servers     = servers
          @port        = port
          @ssl_context = ssl_context
          @tasks       = []
        end


        # Registers accept loop tasks owned by the engine.
        #
        # @param tasks [Array<Async::Task>]
        #
        def accept_tasks=(tasks)
          @tasks = tasks
        end


        # Stops the listener.
        #
        def stop
          @tasks.each(&:stop)
          @servers.each { |s| s.close rescue nil }
        end
      end
    end
  end
end
