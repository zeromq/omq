# frozen_string_literal: true

require "socket"
require "async"

module OMQ
  module ZMTP
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
            host, port = parse_endpoint(endpoint)
            host = "0.0.0.0" if host == "*"
            server = TCPServer.new(host, port)
            actual_port = server.local_address.ip_port
            host_part = host.include?(":") ? "[#{host}]" : host
            resolved  = "tcp://#{host_part}:#{actual_port}"

            accept_task = Reactor.spawn_pump do
              loop do
                client = server.accept
                Reactor.run do
                  engine.handle_accepted(SocketIO.new(client, options: engine.options), endpoint: resolved)
                rescue => e
                  client.close rescue nil
                  raise if !e.is_a?(ProtocolError) && !e.is_a?(EOFError)
                end
              end
            rescue IOError
              # server closed
            end

            Listener.new(resolved, server, accept_task, actual_port)
          end

          # Connects to a TCP endpoint.
          #
          # @param endpoint [String] e.g. "tcp://127.0.0.1:5555"
          # @param engine [Engine]
          # @return [void]
          #
          def connect(endpoint, engine)
            host, port = parse_endpoint(endpoint)
            timeout = engine.options.connect_timeout
            sock = if timeout
                     ::Socket.tcp(host, port, connect_timeout: timeout)
                   else
                     TCPSocket.new(host, port)
                   end
            engine.handle_connected(SocketIO.new(sock, options: engine.options), endpoint: endpoint)
          end

          private

          def parse_endpoint(endpoint)
            # tcp://host:port
            uri = endpoint.sub(%r{\Atcp://}, "")
            host, port_str = uri.rsplit_host_port
            [host, port_str.to_i]
          end
        end

        # Wraps a Ruby TCPSocket/UNIXSocket to provide #read/#write/#close.
        #
        class SocketIO
          # @param socket [TCPSocket, UNIXSocket]
          # @param options [Options, nil] socket options for TCP tuning
          #
          def initialize(socket, options: nil)
            @socket = socket
            if socket.is_a?(TCPSocket) || socket.is_a?(::Socket)
              socket.setsockopt(::Socket::IPPROTO_TCP, ::Socket::TCP_NODELAY, 1)
              apply_tcp_keepalive(socket, options) if options
            end
          end

          # Reads up to n bytes.
          #
          # @param n [Integer]
          # @return [String, nil]
          #
          def read(n)
            @socket.read(n)
          end

          # Writes data.
          #
          # @param data [String]
          # @return [Integer]
          #
          def write(data)
            @socket.write(data)
          end

          # Closes the socket.
          #
          def close
            @socket.close
          rescue IOError
            # already closed
          end

          private

          def apply_tcp_keepalive(socket, options)
            return if options.tcp_keepalive.nil?

            socket.setsockopt(::Socket::SOL_SOCKET, ::Socket::SO_KEEPALIVE,
                              options.tcp_keepalive ? 1 : 0)

            if options.tcp_keepalive
              if options.tcp_keepalive_idle
                socket.setsockopt(::Socket::IPPROTO_TCP, ::Socket::TCP_KEEPIDLE,
                                  options.tcp_keepalive_idle.to_i)
              end

              if options.tcp_keepalive_interval
                socket.setsockopt(::Socket::IPPROTO_TCP, ::Socket::TCP_KEEPINTVL,
                                  options.tcp_keepalive_interval.to_i)
              end

              if options.tcp_keepalive_count
                socket.setsockopt(::Socket::IPPROTO_TCP, ::Socket::TCP_KEEPCNT,
                                  options.tcp_keepalive_count.to_i)
              end
            end
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

          def initialize(endpoint, server, accept_task, port)
            @endpoint = endpoint
            @server = server
            @accept_task = accept_task
            @port = port
          end

          # Stops the listener.
          #
          def stop
            @accept_task.stop
            @server.close rescue nil
          end
        end
      end
    end
  end
end

# Helper to split "host:port" handling IPv6 bracket notation
#
class String
  unless method_defined?(:rsplit_host_port)
    def rsplit_host_port
      if self =~ /\A\[(.+)\]:(\d+)\z/
        [$1, $2]
      elsif self =~ /\A(.+):(\d+)\z/
        [$1, $2]
      else
        [self, "0"]
      end
    end
  end
end
