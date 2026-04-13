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
        @drain     = []              # orphaned queues, drained before active queues
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
      # If the queue still has pending messages it moves to the
      # priority drain list so those messages are consumed before
      # any active connection's messages — preserving FIFO for
      # sequential connections.
      #
      # @param conn [Connection]
      #
      def remove_queue(conn)
        q = @mapping.delete(conn)
        return unless q
        @queues.delete(q)
        @drain << q unless q.empty?
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
          if @closed && @drain.empty? && @queues.all? { |q| q.empty? }
            return nil
          end

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
        @drain.empty? && @queues.all? { |q| q.empty? }
      end


      private


      # Drains orphaned queues first (preserves FIFO for disconnected
      # peers), then tries each active queue once in round-robin order.
      #
      def try_dequeue
        # Priority: drain orphaned queues before serving active ones
        until @drain.empty?
          msg = @drain.first.dequeue(timeout: 0)
          if msg
            return msg
          else
            @drain.shift
          end
        end

        @queues.size.times do
          q = begin
                @cycle.next
              rescue StopIteration
                @cycle = @queues.cycle
                break
              end
          msg = q.dequeue(timeout: 0)
          return msg if msg
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
      def dequeue(timeout: nil)
        @inner.dequeue(timeout: timeout)
      end


      # @return [Boolean]
      #
      def empty?
        @inner.empty?
      end


      # @param item [Object, nil]
      # @return [void]
      #
      def push(item)
        @inner.push(item)
      end

    end
  end
end
