# frozen_string_literal: true

module OMQ
  # Async::Queue-compatible read interface.
  #
  # Automatically included by {Readable}. Provides #dequeue, #pop,
  # #wait, and #each so sockets can be used where an Async::Queue
  # is expected.
  #
  module QueueReadable
    # Dequeues the next message.
    #
    # @param timeout [Numeric, nil] timeout in seconds (overrides
    #   the socket's +read_timeout+ for this call)
    # @return [Array<String>] message parts
    # @raise [IO::TimeoutError] if timeout exceeded
    #
    def dequeue(timeout: @options.read_timeout)
      msg = @recv_mutex.synchronize { @recv_buffer.shift }
      return msg if msg

      batch = Reactor.run { with_timeout(timeout) { @engine.dequeue_recv_batch(Readable::RECV_BATCH_SIZE) } }
      msg = batch.shift
      @recv_mutex.synchronize { @recv_buffer.concat(batch) } unless batch.empty?
      msg
    end

    alias_method :pop, :dequeue

    # Waits for the next message indefinitely (ignores read_timeout).
    #
    # @return [Array<String>] message parts
    #
    def wait
      dequeue(timeout: nil)
    end


    # Yields each received message until the socket is closed or
    # a receive timeout expires.
    #
    # @yield [Array<String>] message parts
    # @return [void]
    #
    def each
      while (msg = receive)
        yield msg
      end
    rescue IO::TimeoutError
      nil
    end
  end


  # Async::Queue-compatible write interface.
  #
  # Automatically included by {Writable}. Provides #enqueue, #push,
  # and #signal so sockets can be used where an Async::Queue is
  # expected.
  #
  module QueueWritable
    # Enqueues one or more messages for sending.
    #
    # @param messages [String, Array<String>]
    # @return [self]
    #
    def enqueue(*messages)
      messages.each { |msg| send(msg) }
      self
    end

    alias_method :push, :enqueue
  end
end
