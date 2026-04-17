# frozen_string_literal: true

# OMQ PEER socket type (ZeroMQ RFC 51).
#
# Not loaded by +require "omq"+; opt in with:
#
#   require "omq/peer"

require "omq"
require_relative "routing/peer"

module OMQ
  # Bidirectional multi-peer socket with routing IDs (ZeroMQ RFC 51).
  #
  # Each connected peer is assigned a 4-byte routing ID. Supports
  # directed sends via #send_to and fair-queued receives.
  class PEER < Socket
    include Readable
    include Writable
    include SingleFrame

    # Creates a new PEER socket.
    #
    # @param endpoints [String, Array<String>, nil] endpoint(s) to connect to
    # @param linger [Numeric] linger period in seconds (Float::INFINITY = wait forever, 0 = drop)
    # @param backend [Object, nil] optional transport backend
    def initialize(endpoints = nil, linger: Float::INFINITY, backend: nil)
      init_engine(:PEER, backend: backend)
      @options.linger = linger
      attach_endpoints(endpoints, default: :connect)
    end


    # Sends a message to a specific peer by routing ID.
    #
    # @param routing_id [String] 4-byte routing ID
    # @param message [String] message body
    # @return [self]
    #
    def send_to(routing_id, message)
      parts = [routing_id.b.freeze, message.b.freeze]
      Reactor.run(timeout: @options.write_timeout) { @engine.enqueue_send(parts) }
      self
    end
  end


  Routing.register(:PEER, Routing::Peer)
end
