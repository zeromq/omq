# frozen_string_literal: true

require "socket"
require "uri"
require "io/stream"

module OMQ
  module Transport
    # TCP transport using Ruby sockets with Async.
    #
    module TCP
      class << self
        # Binds a TCP server.
        #
        # @param endpoint [String] e.g. "tcp://127.0.0.1:5555" or "tcp://*:0"
        # @param engine [Engine]
        # @return [Listener]
        #
        def bind(endpoint, engine)
          host, port = self.parse_endpoint(endpoint)
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
          resolved  = "tcp://#{host_part}:#{actual_port}"
          Listener.new(resolved, servers, actual_port, engine)
        end


        # Validates that the endpoint's host can be resolved.
        #
        # @param endpoint [String]
        # @return [void]
        #
        def validate_endpoint!(endpoint)
          host, _port = parse_endpoint(endpoint)
          Addrinfo.getaddrinfo(host, nil, nil, :STREAM) if host
        end


        # Connects to a TCP endpoint.
        #
        # @param endpoint [String] e.g. "tcp://127.0.0.1:5555"
        # @param engine [Engine]
        # @return [void]
        #
        def connect(endpoint, engine)
          host, port = self.parse_endpoint(endpoint)
          sock = ::Socket.tcp(host, port, connect_timeout: connect_timeout(engine.options))
          apply_buffer_sizes(sock, engine.options)
          engine.handle_connected(IO::Stream::Buffered.wrap(sock), endpoint: endpoint)
        end


        # Connect timeout: cap each attempt at the reconnect interval so a
        # hung connect(2) (e.g. macOS kqueue + IPv6 ECONNREFUSED not delivered)
        # doesn't block the retry loop. Floor at 0.5s for real-network latency.
        #
        def connect_timeout(options)
          ri = options.reconnect_interval
          ri = ri.end if ri.is_a?(Range)
          [ri, 0.5].max
        end


        # Parses a TCP endpoint URI into host and port.
        #
        # @param endpoint [String]
        # @return [Array(String, Integer)]
        #
        def parse_endpoint(endpoint)
          uri = URI.parse(endpoint)
          [uri.hostname, uri.port]
        end


        def apply_buffer_sizes(sock, options)
          sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDBUF, options.sndbuf) if options.sndbuf
          sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, options.rcvbuf) if options.rcvbuf
        end
      end


      # A bound TCP listener.
      #
      class Listener
        # @return [String] resolved endpoint with actual port
        #
        attr_reader :endpoint

        # @return [Integer] bound port
        #
        attr_reader :port

        # @return [Array<TCPServer>] bound server sockets
        #
        attr_reader :servers


        # @param endpoint [String] resolved endpoint URI
        # @param servers [Array<TCPServer>]
        # @param port [Integer] bound port number
        # @param engine [Engine]
        #
        def initialize(endpoint, servers, port, engine)
          @endpoint = endpoint
          @servers  = servers
          @port     = port
          @engine   = engine
          @tasks    = []
        end


        # Spawns accept loop tasks under +parent_task+.
        # Yields an IO::Stream-wrapped client socket for each accepted connection.
        #
        # @param parent_task [Async::Task]
        # @yieldparam io [IO::Stream::Buffered]
        #
        def start_accept_loops(parent_task, &on_accepted)
          @tasks = @servers.map do |server|
            parent_task.async(transient: true, annotation: "tcp accept #{@endpoint}") do
              loop do
                client = server.accept
                TCP.apply_buffer_sizes(client, @engine.options)
                Async::Task.current.defer_stop { on_accepted.call(IO::Stream::Buffered.wrap(client)) }
              end
            rescue Async::Stop
            rescue IOError
              # server closed
            rescue => e
              $stderr.write("omq: tcp accept: #{e.class}: #{e.message}\n#{e.backtrace&.first}\n") if OMQ::DEBUG
            ensure
              server.close rescue nil
            end
          end
        end


        # Stops the listener and closes all server sockets.
        #
        # @return [void]
        #
        def stop
          @tasks.each(&:stop)
          @servers.each { |s| s.close rescue nil }
        end
      end
    end
  end
end
