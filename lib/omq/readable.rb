# frozen_string_literal: true

require "timeout"

module OMQ
  # Pure Ruby Readable mixin. Dequeues messages from the engine's recv queue.
  #
  module Readable
    # Receives the next message.
    #
    # @return [Array<String>] message parts
    # @raise [IO::TimeoutError] if read_timeout exceeded
    #
    def receive
      Reactor.run { with_timeout(@options.read_timeout) { @engine.dequeue_recv } }
    end

    # Receives up to +max+ messages. Blocks until at least one is
    # available, then drains the recv queue without blocking.
    #
    # @param max [Integer] maximum messages to return
    # @return [Array<Array<String>>] array of messages
    #
    def receive_messages(max)
      Reactor.run { with_timeout(@options.read_timeout) { @engine.dequeue_recv_batch(max) } }
    end

    # Waits until the socket is readable.
    #
    # @param timeout [Numeric, nil] timeout in seconds
    # @return [true]
    #
    def wait_readable(timeout = @options.read_timeout)
      true
    end
  end
end
