# frozen_string_literal: true

require "async"
require "async/queue"
require "async/limited_queue"

module OMQ
  # Routing strategies for each ZMQ socket type.
  #
  # Each strategy manages how messages flow between connections and
  # the socket's send/recv queues.
  #
  module Routing
    # Maximum messages to drain from the send queue per flush cycle.
    MAX_SEND_BATCH = 64

    # Shared frozen empty binary string to avoid repeated allocations.
    EMPTY_BINARY = "".b.freeze

    # Drains up to +max+ additional messages from +queue+ into +batch+
    # without blocking. Call after the initial blocking dequeue.
    #
    # @param queue [Async::LimitedQueue]
    # @param batch [Array]
    # @param max [Integer]
    # @return [void]
    #
    def self.drain_send_queue(queue, batch, max = MAX_SEND_BATCH)
      while batch.size < max
        msg = queue.dequeue(timeout: 0)
        break unless msg
        batch << msg
      end
    end

    # Returns the routing strategy class for a socket type.
    #
    # @param socket_type [Symbol] e.g. :PAIR, :REQ
    # @return [Class]
    #
    def self.for(socket_type)
      case socket_type
      when :PAIR   then Pair
      when :REQ    then Req
      when :REP    then Rep
      when :DEALER then Dealer
      when :ROUTER then Router
      when :PUB    then Pub
      when :SUB    then Sub
      when :XPUB   then XPub
      when :XSUB   then XSub
      when :PUSH    then Push
      when :PULL    then Pull
      when :CLIENT  then Client
      when :SERVER  then Server
      when :RADIO   then Radio
      when :DISH    then Dish
      when :SCATTER then Scatter
      when :GATHER  then Gather
      when :PEER    then Peer
      when :CHANNEL then Channel
      else raise ArgumentError, "unknown socket type: #{socket_type}"
      end
    end
  end
end
