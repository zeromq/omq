# frozen_string_literal: true

require "async"
require "async/queue"
require "async/limited_queue"

module OMQ
  module ZMTP
    # Routing strategies for each ZMQ socket type.
    #
    # Each strategy manages how messages flow between connections and
    # the socket's send/recv queues.
    #
    module Routing
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
        when :PUSH   then Push
        when :PULL   then Pull
        else raise ArgumentError, "unknown socket type: #{socket_type}"
        end
      end
    end
  end
end
