# frozen_string_literal: true

module OMQ
  class Engine
    # Performs ZMTP handshake and registers a new connection.
    #
    class ConnectionSetup
      # @param io [#read, #write, #close] underlying transport stream
      # @param engine [Engine]
      # @param as_server [Boolean]
      # @param endpoint [String, nil]
      # @param done [Async::Promise, nil] resolved when connection is lost
      # @return [Connection]
      #
      def self.run(io, engine, as_server:, endpoint: nil, done: nil)
        new(engine).run(io, as_server: as_server, endpoint: endpoint, done: done)
      end


      # @param engine [Engine]
      #
      def initialize(engine)
        @engine = engine
      end


      # Performs the ZMTP handshake, starts heartbeat, and registers the connection.
      #
      # @param io [#read, #write, #close]
      # @param as_server [Boolean]
      # @param endpoint [String, nil]
      # @param done [Async::Promise, nil] resolved when connection is lost
      # @return [Connection]
      #
      def run(io, as_server:, endpoint: nil, done: nil)
        conn = build_connection(io, as_server)
        conn.handshake!
        Heartbeat.start(@engine.parent_task, conn, @engine.options, @engine.tasks)
        conn = @engine.connection_wrapper.call(conn) if @engine.connection_wrapper
        register(conn, endpoint, done)
        @engine.emit_monitor_event(:handshake_succeeded, endpoint: endpoint)
        conn
      rescue Protocol::ZMTP::Error, *CONNECTION_LOST => error
        @engine.emit_monitor_event(:handshake_failed, endpoint: endpoint, detail: { error: error })
        conn&.close
        raise
      end

      private

      def build_connection(io, as_server)
        Protocol::ZMTP::Connection.new(
          io,
          socket_type:      @engine.socket_type.to_s,
          identity:         @engine.options.identity,
          as_server:        as_server,
          mechanism:        @engine.options.mechanism&.dup,
          max_message_size: @engine.options.max_message_size,
        )
      end


      def register(conn, endpoint, done)
        @engine.connections[conn] = Engine::ConnectionRecord.new(endpoint: endpoint, done: done)
        @engine.routing.connection_added(conn)
        @engine.peer_connected.resolve(conn)
      end
    end
  end
end
