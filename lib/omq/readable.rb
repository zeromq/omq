# frozen_string_literal: true

require "timeout"

module OMQ
  # Pure Ruby Readable mixin. Dequeues messages from the engine's recv queue.
  #
  module Readable
    # Maximum messages to prefetch from the recv queue per drain.
    RECV_BATCH_SIZE = 64

    # Receives the next message. Internally prefetches up to
    # {RECV_BATCH_SIZE} messages per queue drain to amortize
    # scheduling overhead.
    #
    # @return [Array<String>] message parts
    # @raise [IO::TimeoutError] if read_timeout exceeded
    #
    def receive
      if @recv_buffer && @recv_buffer.size > 0
        @recv_buffer.shift
      else
        batch = Reactor.run { with_timeout(@options.read_timeout) { @engine.dequeue_recv_batch(RECV_BATCH_SIZE) } }
        if batch.size == 1
          batch.first
        else
          @recv_buffer = batch
          @recv_buffer.shift
        end
      end
    end

    # Receives up to +max+ messages. Blocks until at least one is
    # available, then drains the recv queue without blocking.
    #
    # @param max [Integer] maximum messages to return
    # @return [Array<Array<String>>] array of messages
    #
    def receive_messages(max)
      if @recv_buffer && @recv_buffer.size > 0
        # Drain buffer first, then queue if needed
        if @recv_buffer.size >= max
          @recv_buffer.shift(max)
        else
          batch = @recv_buffer
          @recv_buffer = nil
          remaining = max - batch.size
          more = Reactor.run { @engine.dequeue_recv_batch(remaining) } rescue nil
          batch.concat(more) if more
          batch
        end
      else
        Reactor.run { with_timeout(@options.read_timeout) { @engine.dequeue_recv_batch(max) } }
      end
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
