# frozen_string_literal: true

module OMQ
  class Engine
    # Owns the full arc of one connection: handshake → ready → closed.
    #
    # Centralizes the ordering of side effects (monitor events, routing
    # registration, promise resolution, reconnect scheduling) so the
    # sequence lives in one place instead of being scattered across
    # Engine, ConnectionSetup, and close paths.
    #
    # State machine:
    #
    #   new ──┬── :handshaking ── :ready ── :closed
    #         └── :ready ── :closed            (inproc fast path)
    #
    # #lost! and #close! are idempotent — the state guard ensures side
    # effects run exactly once even if multiple pumps race to report a
    # lost connection.
    #
    class ConnectionLifecycle
      class InvalidTransition < RuntimeError; end

      STATES = %i[new handshaking ready closed].freeze

      TRANSITIONS = {
        new:         %i[handshaking ready closed].freeze,
        handshaking: %i[ready closed].freeze,
        ready:       %i[closed].freeze,
        closed:      [].freeze,
      }.freeze


      # @return [Protocol::ZMTP::Connection, Transport::Inproc::DirectPipe, nil]
      attr_reader :conn

      # @return [String, nil]
      attr_reader :endpoint

      # @return [Symbol] current state
      attr_reader :state

      # @return [Async::Barrier] holds all per-connection pump tasks
      #   (send pump, recv pump, reaper, heartbeat). When the connection
      #   is torn down, {#tear_down!} calls `@barrier.stop` to take down
      #   every sibling task atomically — so the first pump to see a
      #   disconnect takes down all the others.
      attr_reader :barrier


      # @param engine [Engine]
      # @param endpoint [String, nil]
      # @param done [Async::Promise, nil] resolved when connection is lost
      #
      def initialize(engine, endpoint: nil, done: nil)
        @engine   = engine
        @endpoint = endpoint
        @done     = done
        @state    = :new
        @conn     = nil
        # Nest the per-connection barrier under the socket-level barrier
        # so every pump spawned via +@barrier.async+ is also tracked by
        # the socket barrier — {Engine#stop}/{Engine#close} cascade
        # through in one call.
        @barrier  = Async::Barrier.new(parent: engine.barrier)
      end


      # Performs the ZMTP handshake and transitions to :ready.
      #
      # @param io [#read, #write, #close]
      # @param as_server [Boolean]
      # @return [Protocol::ZMTP::Connection]
      #
      def handshake!(io, as_server:)
        transition!(:handshaking)
        conn = Protocol::ZMTP::Connection.new(
          io,
          socket_type:      @engine.socket_type.to_s,
          identity:         @engine.options.identity,
          as_server:        as_server,
          mechanism:        @engine.options.mechanism&.dup,
          max_message_size: @engine.options.max_message_size,
        )
        conn.handshake!
        Heartbeat.start(@barrier, conn, @engine.options, @engine.tasks)
        ready!(conn)
        @conn
      rescue Protocol::ZMTP::Error, *CONNECTION_LOST => error
        @engine.emit_monitor_event(:handshake_failed, endpoint: @endpoint, detail: { error: error })
        conn&.close
        transition!(:closed)
        raise
      end


      # Registers an already-connected inproc pipe as :ready.
      # No handshake — inproc DirectPipe bypasses ZMTP entirely.
      #
      # @param pipe [Transport::Inproc::DirectPipe]
      #
      def ready_direct!(pipe)
        ready!(pipe)
      end


      # Transitions to :closed, running the full loss sequence:
      # routing removal, monitor event, reconnect scheduling.
      # Idempotent: a no-op if already :closed.
      #
      def lost!
        tear_down!(reconnect: true)
      end


      # Transitions to :closed without scheduling a reconnect.
      # Used by shutdown paths (Engine#close, #disconnect, #unbind).
      # Idempotent.
      #
      def close!
        tear_down!(reconnect: false)
      end


      private

      def ready!(conn)
        conn  = @engine.connection_wrapper.call(conn) if @engine.connection_wrapper
        @conn = conn
        @engine.connections[@conn] = self
        @engine.emit_monitor_event(:handshake_succeeded, endpoint: @endpoint)
        @engine.routing.connection_added(@conn)
        @engine.peer_connected.resolve(@conn)
        transition!(:ready)
        # No supervisor if nothing to supervise: inproc DirectPipes
        # wire the recv/send paths synchronously (no task-based pumps),
        # and isolated unit tests use a FakeEngine without pumps at all.
        # Waiting on an empty barrier returns immediately and would
        # tear the connection down right after registering.
        start_supervisor unless @barrier.empty?
      end


      # Spawns a supervisor task on the *socket-level* barrier (not the
      # per-connection barrier) that blocks on the first pump to finish
      # and then triggers teardown.
      #
      # Keeping the supervisor out of the per-connection barrier avoids
      # the self-stop problem: stopping the current task raises
      # Async::Cancel synchronously and unwinds before side effects can
      # run. Placing it on the socket barrier means {Engine#stop} /
      # {Engine#close} cascade-cancels the supervisor, whose +ensure+
      # runs the ordered disconnect side effects once.
      #
      def start_supervisor
        @supervisor = @engine.barrier.async(transient: true, annotation: "conn supervisor") do
          @barrier.wait do |task|
            task.wait
            break
          end
        rescue Async::Stop, Async::Cancel
          # socket or supervisor cancelled externally (socket closing)
        rescue Protocol::ZMTP::Error, *CONNECTION_LOST
          # expected pump exit on disconnect
        ensure
          lost!
        end
      end


      def tear_down!(reconnect:)
        return if @state == :closed
        transition!(:closed)
        @engine.connections.delete(@conn)
        @engine.routing.connection_removed(@conn) if @conn
        @conn&.close rescue nil
        @engine.emit_monitor_event(:disconnected, endpoint: @endpoint)
        @done&.resolve(true)
        @engine.resolve_all_peers_gone_if_empty
        @engine.maybe_reconnect(@endpoint) if reconnect
        # Cancel every sibling pump of this connection. The caller is
        # the supervisor task, which is NOT in the barrier — so there
        # is no self-stop risk.
        @barrier.stop
      end


      def transition!(new_state)
        allowed = TRANSITIONS[@state]
        unless allowed&.include?(new_state)
          raise InvalidTransition, "#{@state} → #{new_state}"
        end
        @state = new_state
      end
    end
  end
end
