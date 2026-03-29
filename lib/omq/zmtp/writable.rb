# frozen_string_literal: true

require "timeout"

module OMQ
  module ZMTP
    # Pure Ruby Writable mixin. Enqueues messages to the engine's send path.
    #
    module Writable
      # Sends a message.
      #
      # @param message [String, Array<String>] message parts
      # @return [self]
      # @raise [IO::TimeoutError] if write_timeout exceeded
      #
      def send(message)
        parts = message.is_a?(Array) ? message : [message]
        raise ArgumentError, "message has no parts" if parts.empty?
        if parts.frozen?
          parts = parts.map { |p| p.to_str.b.freeze }
        else
          parts.map! { |p| p.to_str.b.freeze }
        end
        parts.freeze

        with_timeout(@options.write_timeout) { @engine.enqueue_send(parts) }
        self
      end

      # Sends a message (chainable).
      #
      # @param message [String, Array<String>]
      # @return [self]
      #
      def <<(message)
        send(message)
      end

      # Waits until the socket is writable.
      #
      # @param timeout [Numeric, nil] timeout in seconds
      # @return [true]
      #
      def wait_writable(timeout = @options.write_timeout)
        true
      end
    end
  end
end
