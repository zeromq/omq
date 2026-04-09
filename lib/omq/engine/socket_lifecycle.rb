# frozen_string_literal: true

module OMQ
  class Engine
    # Owns the socket-level state: `:new → :open → :closing → :closed`,
    # the first-peer / last-peer signaling promises, the reconnect flag,
    # and the captured parent task for the socket's task tree.
    #
    # Engine delegates state queries here and uses it to coordinate the
    # ordering of close-time side effects. This consolidates six ivars
    # (`@state`, `@peer_connected`, `@all_peers_gone`, `@reconnect_enabled`,
    # `@parent_task`, `@on_io_thread`) into one cohesive object with
    # explicit transitions.
    #
    class SocketLifecycle
      class InvalidTransition < RuntimeError; end

      STATES = %i[new open closing closed].freeze

      TRANSITIONS = {
        new:     %i[open closed].freeze,
        open:    %i[closing closed].freeze,
        closing: %i[closed].freeze,
        closed:  [].freeze,
      }.freeze


      # @return [Symbol]
      attr_reader :state

      # @return [Async::Promise] resolves with the first connected peer
      attr_reader :peer_connected

      # @return [Async::Promise] resolves once all peers are gone (after having had peers)
      attr_reader :all_peers_gone

      # @return [Async::Task, nil] root of the socket's task tree
      attr_reader :parent_task

      # @return [Boolean] true if parent_task is the shared Reactor thread
      attr_reader :on_io_thread

      # @return [Boolean] whether auto-reconnect is enabled
      attr_accessor :reconnect_enabled


      def initialize
        @state             = :new
        @peer_connected    = Async::Promise.new
        @all_peers_gone    = Async::Promise.new
        @reconnect_enabled = true
        @parent_task       = nil
        @on_io_thread      = false
      end


      def open?      = @state == :open
      def closing?   = @state == :closing
      def closed?    = @state == :closed
      def alive?     = @state == :new || @state == :open


      # Captures the current Async task (or the shared Reactor root) as
      # this socket's task tree root. Transitions `:new → :open`.
      #
      # @param linger [Numeric, nil] used to register the Reactor linger slot
      #   when falling back to the IO thread
      # @return [Boolean] true on first-time capture, false if already captured
      #
      def capture_parent_task(linger:)
        return false if @parent_task
        if Async::Task.current?
          @parent_task = Async::Task.current
        else
          @parent_task  = Reactor.root_task
          @on_io_thread = true
          Reactor.track_linger(linger)
        end
        transition!(:open)
        true
      end


      # Transitions `:open → :closing`.
      def start_closing!
        transition!(:closing)
      end


      # Transitions `:closing → :closed` (or `:new → :closed` for
      # never-opened sockets).
      def finish_closing!
        transition!(:closed)
      end


      # Resolves `all_peers_gone` if we had peers and now have none.
      # @param connections [Hash] current connection map
      def resolve_all_peers_gone_if_empty(connections)
        return unless @peer_connected.resolved? && connections.empty?
        @all_peers_gone.resolve(true)
      end


      private

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
