# frozen_string_literal: true

require "socket"
require "async"

module OMQ
  module ZMTP
    module Transport
      # IPC transport using Unix domain sockets.
      #
      # Supports both file-based paths and Linux abstract namespace
      # (paths starting with @).
      #
      module IPC
        class << self
          # Binds an IPC server.
          #
          # @param endpoint [String] e.g. "ipc:///tmp/my.sock" or "ipc://@abstract"
          # @param engine [Engine]
          # @return [Listener]
          #
          def bind(endpoint, engine)
            path = parse_path(endpoint)
            sock_path = to_socket_path(path)

            # Remove stale socket file for file-based paths
            File.delete(sock_path) if !abstract?(path) && File.exist?(sock_path)

            server = UNIXServer.new(sock_path)

            accept_task = Reactor.spawn_pump do
              loop do
                client = server.accept
                Reactor.run do
                  engine.handle_accepted(TCP::SocketIO.new(client), endpoint: endpoint)
                rescue => e
                  client.close rescue nil
                  raise if !e.is_a?(ProtocolError) && !e.is_a?(EOFError)
                end
              end
            rescue IOError
              # server closed
            end

            Listener.new(endpoint, server, accept_task, path)
          end

          # Connects to an IPC endpoint.
          #
          # @param endpoint [String]
          # @param engine [Engine]
          # @return [void]
          #
          def connect(endpoint, engine)
            path = parse_path(endpoint)
            sock_path = to_socket_path(path)
            sock = UNIXSocket.new(sock_path)
            engine.handle_connected(TCP::SocketIO.new(sock), endpoint: endpoint)
          end

          private

          # Extracts path from "ipc://path".
          #
          def parse_path(endpoint)
            endpoint.sub(%r{\Aipc://}, "")
          end

          # Converts @ prefix to \0 for abstract namespace.
          #
          def to_socket_path(path)
            if abstract?(path)
              "\0#{path[1..]}"
            else
              path
            end
          end

          # @return [Boolean] true if abstract namespace path
          #
          def abstract?(path)
            path.start_with?("@")
          end
        end

        # A bound IPC listener.
        #
        class Listener
          # @return [String] the endpoint
          #
          attr_reader :endpoint

          def initialize(endpoint, server, accept_task, path)
            @endpoint = endpoint
            @server = server
            @accept_task = accept_task
            @path = path
          end

          # Stops the listener.
          #
          def stop
            @accept_task.stop
            @server.close rescue nil
            # Clean up socket file for file-based paths
            unless @path.start_with?("@")
              File.delete(@path) rescue nil
            end
          end
        end
      end
    end
  end
end
