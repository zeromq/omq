# frozen_string_literal: true

# OMQ CHANNEL socket type (ZeroMQ RFC 52).
#
# Not loaded by +require "omq"+; opt in with:
#
#   require "omq/channel"

require "omq"
require_relative "routing/channel"

module OMQ
  # Exclusive 1-to-1 bidirectional socket (ZeroMQ RFC 52).
  #
  # Allows exactly one peer connection. Both sides can send and receive.
  class CHANNEL < Socket
    include Readable
    include Writable
    include SingleFrame

    # Creates a new CHANNEL socket.
    #
    # @param endpoints [String, Array<String>, nil] endpoint(s) to connect to
    # @param linger [Numeric] linger period in seconds (Float::INFINITY = wait forever, 0 = drop)
    # @param backend [Object, nil] optional transport backend
    def initialize(endpoints = nil, linger: Float::INFINITY, backend: nil)
      init_engine(:CHANNEL, backend: backend)
      @options.linger = linger
      attach_endpoints(endpoints, default: :connect)
    end
  end


  Routing.register(:CHANNEL, Routing::Channel)
end
