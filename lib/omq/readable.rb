# frozen_string_literal: true

require "timeout"

module OMQ
  # Pure Ruby Readable mixin. Dequeues messages from the engine's recv queue.
  #
  module Readable
    include QueueReadable

    # Maximum messages to prefetch from the recv queue per drain.
    RECV_BATCH_SIZE = 64


    # Receives the next message. Returns from a local prefetch
    # buffer when available, otherwise drains up to
    # {RECV_BATCH_SIZE} messages from the recv queue in one
    # synchronized dequeue.
    #
    # @return [Array<String>] message parts
    # @raise [IO::TimeoutError] if read_timeout exceeded
    #
    def receive
      @recv_mutex.synchronize { @recv_buffer.shift } || fill_recv_buffer
    end


    # Waits until the socket is readable.
    #
    # @param timeout [Numeric, nil] timeout in seconds
    # @return [true]
    #
    def wait_readable(timeout = @options.read_timeout)
      true
    end

    private

    def fill_recv_buffer
      batch = Reactor.run { with_timeout(@options.read_timeout) { @engine.dequeue_recv_batch(RECV_BATCH_SIZE) } }
      msg = batch.shift
      @recv_mutex.synchronize { @recv_buffer.concat(batch) } unless batch.empty?
      msg
    end
  end
end
