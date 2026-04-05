# frozen_string_literal: true

module OMQ
  module Routing
    # Mixin that adds per-connection recv queue setup for fair-queued sockets.
    #
    # Including classes must have @engine, @recv_queue (FairQueue), and @tasks.
    #
    module FairRecv
      private

      # Creates a per-connection recv queue, registers it with @recv_queue,
      # and starts a recv pump for the connection. Called from #connection_added.
      #
      # @param conn [Connection]
      # @yield [msg] optional per-message transform
      #
      def add_fair_recv_connection(conn, &transform)
        conn_q    = Routing.build_queue(@engine.options.recv_hwm, :block)
        signaling = SignalingQueue.new(conn_q, @recv_queue)
        @recv_queue.add_queue(conn, conn_q)
        task      = @engine.start_recv_pump(conn, signaling, &transform)
        @tasks << task if task
      end
    end
  end
end
