# frozen_string_literal: true

require "timeout"

module OMQ
  # Pure Ruby Writable mixin. Enqueues messages to the engine's send path.
  #
  module Writable
    include QueueWritable


    # Sends a message.
    #
    # Caller owns the message parts. Don't mutate them after sending — especially
    # with inproc transport or PUB fan-out, where a single reference can be shared
    # across peers and read later by the send pump.
    #
    # @param message [String, Array<String>] message parts
    # @return [self]
    # @raise [IO::TimeoutError] if write_timeout exceeded
    #
    def send(message)
      parts = message.is_a?(Array) ? message : [message]
      raise ArgumentError, "message has no parts" if parts.empty?

      if @engine.on_io_thread?
        Reactor.run(timeout: @options.write_timeout) { @engine.enqueue_send(parts) }
      elsif (timeout = @options.write_timeout)
        Async::Task.current.with_timeout(timeout, IO::TimeoutError) { @engine.enqueue_send(parts) }
      else
        @engine.enqueue_send(parts)
      end

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
