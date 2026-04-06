# frozen_string_literal: true

module OMQ
  module Routing
    # Per-connection recv queue aggregator.
    #
    # Maintains one bounded queue per connected peer. #dequeue
    # returns the next available message from any peer in fair
    # round-robin order, blocking until one arrives.
    #
    # Recv pumps do not enqueue directly — they write through a
    # SignalingQueue wrapper, which also wakes a blocked #dequeue.
    #
    class FairQueue
      # Creates an empty fair queue with no per-connection queues.
      #
      def initialize
        @queues    = []              # ordered list of per-connection inner queues
        @mapping   = {}              # connection => inner queue
        @cycle     = @queues.cycle  # live reference — sees adds/removes
        @condition = Async::Condition.new
        @pending   = 0              # signals received before #dequeue waits
        @closed    = false
      end


      # Registers a per-connection queue. Called when a connection is added.
      #
      # @param conn [Connection]
      # @param q [Async::LimitedQueue]
      #
      def add_queue(conn, q)
        @mapping[conn] = q
        @queues << q
      end


      # Removes the per-connection queue for a disconnected peer.
      #
      # If the queue is empty it is removed immediately. If it still has
      # pending messages it is kept in @queues so the application can drain
      # them via #dequeue; it will be cleaned up lazily by try_dequeue once
      # it is empty.
      #
      # @param conn [Connection]
      #
      def remove_queue(conn)
        q = @mapping.delete(conn)
        return unless q
        @queues.delete(q) if q.empty?
        # Non-empty orphaned queues stay in @queues until drained
      end


      # Wakes a blocked #dequeue. Called by SignalingQueue after each enqueue.
      #
      def signal
        @pending += 1
        @condition.signal
      end


      # Returns the next message from any per-connection queue, in fair
      # round-robin order. Blocks until a message is available.
      #
      # Pass +timeout: 0+ for a non-blocking poll (returns nil immediately
      # if no messages are available).
      #
      # @param timeout [Numeric, nil] 0 = non-blocking, nil = block forever
      # @return [Array<String>, nil]
      #
      def dequeue(timeout: nil)
        return try_dequeue if timeout == 0

        loop do
          return nil if @closed && @queues.all?(&:empty?)

          msg = try_dequeue
          return msg if msg

          if @pending > 0
            @pending -= 1
            next
          end

          @condition.wait
        end
      end


      # Injects a nil sentinel to unblock a waiting #dequeue.
      # Called by Engine on close or fatal error.
      #
      def push(nil_sentinel)
        @closed = true
        @condition.signal
      end


      # @return [Boolean]
      #
      def empty?
        @queues.all?(&:empty?)
      end

      private

      # Tries each per-connection queue once in round-robin order.
      # Returns the first message found, or nil if all are empty.
      # Lazily removes empty orphaned queues (disconnected peers that have
      # been fully drained).
      #
      def try_dequeue
        @queues.size.times do
          q = begin
                @cycle.next
              rescue StopIteration
                @cycle = @queues.cycle
                break
              end
          msg = q.dequeue(timeout: 0)
          return msg if msg
          if q.empty? && !@mapping.value?(q)
            @queues.delete(q)
            break
          end
        end
        nil
      end
    end


    # Wraps a per-connection bounded queue so that each #enqueue also
    # signals the FairQueue to wake a blocked #dequeue.
    #
    class SignalingQueue
      # @param inner [Async::LimitedQueue] the per-connection bounded queue
      # @param fair_queue [FairQueue] the parent fair queue to signal on enqueue
      #
      def initialize(inner, fair_queue)
        @inner = inner
        @fair  = fair_queue
      end


      # Enqueues a message and signals the fair queue.
      #
      # @param msg [Array<String>]
      # @return [void]
      #
      def enqueue(msg)
        @inner.enqueue(msg)
        @fair.signal
      end


      # @param timeout [Numeric, nil] dequeue timeout
      # @return [Array<String>, nil]
      #
      def dequeue(timeout: nil) = @inner.dequeue(timeout: timeout)

      # @return [Boolean]
      #
      def empty?                = @inner.empty?

      # @param item [Object, nil]
      # @return [void]
      #
      def push(item)            = @inner.push(item)
    end
  end
end
