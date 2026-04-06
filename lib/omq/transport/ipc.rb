# frozen_string_literal: true

require "socket"
require "io/stream"

module OMQ
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

          Listener.new(endpoint, server, path)
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
          engine.handle_connected(IO::Stream::Buffered.wrap(sock), endpoint: endpoint)
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

        # @return [UNIXServer] the server socket
        #
        attr_reader :server


        # @param endpoint [String] the IPC endpoint URI
        # @param server [UNIXServer]
        # @param path [String] filesystem or abstract namespace path
        #
        def initialize(endpoint, server, path)
          @endpoint = endpoint
          @server   = server
          @path     = path
          @task     = nil
        end


        # Spawns an accept loop task under +parent_task+.
        # Yields an IO::Stream-wrapped client socket for each accepted connection.
        #
        # @param parent_task [Async::Task]
        # @yieldparam io [IO::Stream::Buffered]
        #
        def start_accept_loops(parent_task, &on_accepted)
          @task = parent_task.async(transient: true, annotation: "ipc accept #{@endpoint}") do
            loop do
              client = @server.accept
              Async::Task.current.defer_stop { on_accepted.call(IO::Stream::Buffered.wrap(client)) }
            end
          rescue Async::Stop
          rescue IOError
            # server closed
          ensure
            @server.close rescue nil
          end
        end


        # Stops the listener and removes the socket file.
        #
        # @return [void]
        #
        def stop
          @task&.stop
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
