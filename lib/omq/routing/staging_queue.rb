# frozen_string_literal: true

module OMQ
  module Routing
    # Bounded FIFO queue for staging unsent messages.
    #
    # Wraps an +Async::LimitedQueue+ for backpressure, with a small
    # prepend buffer checked first on dequeue (same trick as the
    # prefetch buffer in {OMQ::Readable#receive}).
    #
    class StagingQueue
      # @param max [Integer, nil] capacity (nil or 0 = unbounded)
      #
      def initialize(max = nil)
        @max   = (max && max > 0) ? max : nil
        @queue = @max ? Async::LimitedQueue.new(@max) : Async::Queue.new
        @head  = []
        @mu    = Mutex.new
      end


      # Appends a message to the back.
      # Blocks (fiber-yields) when at capacity.
      #
      # @param msg [Array<String>]
      # @return [void]
      #
      def enqueue(msg)
        @queue.enqueue(msg)
      end


      # Inserts a message at the front (for re-staging after a
      # failed drain).  Drops the message if the staging queue is
      # already at capacity (messages sent to a peer that disconnected
      # may be lost -- same as ZMQ).
      #
      # @param msg [Array<String>]
      # @return [void]
      #
      def prepend(msg)
        @mu.synchronize do
          return if @max && @head.size >= @max
          @head.push(msg)
        end
      end


      # Returns the first message: from the prepend buffer if
      # non-empty, otherwise non-blocking dequeue from the main queue.
      #
      # @return [Array<String>, nil]
      #
      def dequeue
        @mu.synchronize { @head.shift } || @queue.dequeue(timeout: 0)
      end


      # @return [Boolean]
      #
      def empty?
        @mu.synchronize { @head.empty? } && @queue.empty?
      end
    end
  end
end
