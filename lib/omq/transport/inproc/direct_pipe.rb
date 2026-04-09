# frozen_string_literal: true

module OMQ
  module Transport
    module Inproc
      # A direct in-process pipe that transfers Ruby arrays through queues.
      #
      # Implements the same interface as Connection so routing strategies
      # can use it transparently.
      #
      # When a routing strategy sets {#direct_recv_queue} on a pipe,
      # {#send_message} enqueues directly into the peer's recv queue,
      # bypassing the intermediate pipe queues and the recv pump task.
      # This reduces inproc from 3 queue hops to 2 (send_queue →
      # recv_queue), eliminating the internal pipe queue in between.
      #
      class DirectPipe
        # @return [String] peer's socket type
        #
        attr_reader :peer_socket_type


        # @return [String] peer's identity
        #
        attr_reader :peer_identity


        # @return [DirectPipe, nil] the other end of this pipe pair
        #
        attr_accessor :peer


        # @return [Async::LimitedQueue, nil] when set, {#send_message}
        #   enqueues directly here instead of using the internal queue
        #
        attr_reader :direct_recv_queue


        # @return [Proc, nil] optional transform applied before
        #   enqueuing into {#direct_recv_queue}
        #
        attr_accessor :direct_recv_transform


        # @param send_queue [Async::Queue, nil] outgoing command queue
        #   (nil for non-PUB/SUB types that don't exchange commands)
        # @param receive_queue [Async::Queue, nil] incoming command queue
        # @param peer_identity [String]
        # @param peer_type [String]
        #
        def initialize(send_queue: nil, receive_queue: nil, peer_identity:, peer_type:)
          @send_queue            = send_queue
          @receive_queue         = receive_queue
          @peer_identity         = peer_identity || "".b
          @peer_socket_type      = peer_type
          @closed                = false
          @peer                  = nil
          @direct_recv_queue     = nil
          @direct_recv_transform = nil
          @pending_direct        = nil
        end


        # Sets the direct recv queue. Drains any messages that were
        # buffered before the queue was available.
        #
        # @param queue [Async::LimitedQueue, nil]
        # @return [void]
        #
        def direct_recv_queue=(queue)
          @direct_recv_queue = queue
          if queue && @pending_direct
            @pending_direct.each { |msg| queue.enqueue(msg) }
            @pending_direct = nil
          end
        end


        # Sends a multi-frame message.
        #
        # @param parts [Array<String>]
        # @return [void]
        #
        def send_message(parts)
          raise IOError, "closed" if @closed
          if @direct_recv_queue
            @direct_recv_queue.enqueue(apply_transform(parts))
          elsif @send_queue
            @send_queue.enqueue(parts)
          else
            (@pending_direct ||= []) << apply_transform(parts)
          end
        end


        alias write_message send_message


        # Batched form, for parity with Protocol::ZMTP::Connection. The
        # work-stealing pumps call this when they dequeue more than one
        # message at once; DirectPipe just loops — no mutex to amortize.
        #
        # @param messages [Array<Array<String>>]
        # @return [void]
        #
        def write_messages(messages)
          messages.each { |parts| send_message(parts) }
        end


        # @return [Boolean] always false; inproc pipes are never encrypted
        #
        def encrypted? = false

        # No-op — inproc has no IO buffer to flush.
        #
        # @return [nil]
        #
        def flush = nil


        # Receives a multi-frame message.
        #
        # @return [Array<String>]
        # @raise [EOFError] if closed
        #
        def receive_message
          loop do
            item = @receive_queue.dequeue
            raise EOFError, "connection closed" if item.nil?
            if item.is_a?(Array) && item.first == :command
              yield Protocol::ZMTP::Codec::Frame.new(item[1].to_body, command: true) if block_given?
              next
            end
            return item
          end
        end


        # Sends a command via the internal command queue.
        # Only available for PUB/SUB-family pipes.
        #
        # @param command [Protocol::ZMTP::Codec::Command]
        #
        def send_command(command)
          raise IOError, "closed" if @closed
          @send_queue.enqueue([:command, command])
        end


        # Reads one command frame from the internal command queue.
        # Used by PUB/XPUB subscription listeners.
        #
        # @return [Protocol::ZMTP::Codec::Frame]
        #
        def read_frame
          loop do
            item = @receive_queue.dequeue
            raise EOFError, "connection closed" if item.nil?
            if item.is_a?(Array) && item.first == :command
              return Protocol::ZMTP::Codec::Frame.new(item[1].to_body, command: true)
            end
          end
        end


        # Closes this pipe end and sends a nil sentinel to the peer.
        #
        # @return [void]
        #
        def close
          return if @closed
          @closed = true
          @send_queue&.enqueue(nil) # close sentinel
        end

        private

        def apply_transform(parts)
          @direct_recv_transform ? @direct_recv_transform.call(parts).freeze : parts
        end
      end
    end
  end
end
