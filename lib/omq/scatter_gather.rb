# frozen_string_literal: true

# OMQ SCATTER/GATHER socket types (ZeroMQ RFC 49).
#
# Not loaded by +require "omq"+; opt in with:
#
#   require "omq/scatter_gather"

require "omq"
require_relative "routing/scatter"
require_relative "routing/gather"

module OMQ
  # Pipeline sender socket that round-robins to GATHER peers (ZeroMQ RFC 49).
  class SCATTER < Socket
    include Writable
    include SingleFrame

    # Creates a new SCATTER socket.
    #
    # @param endpoints [String, Array<String>, nil] endpoint(s) to connect to
    # @param linger [Numeric] linger period in seconds (Float::INFINITY = wait forever, 0 = drop)
    # @param send_hwm [Integer, nil] send high-water mark
    # @param send_timeout [Integer, nil] send timeout in seconds
    # @param backend [Object, nil] optional transport backend
    def initialize(endpoints = nil, linger: Float::INFINITY, send_hwm: nil, send_timeout: nil, backend: nil)
      init_engine(:SCATTER, send_hwm: send_hwm, send_timeout: send_timeout, backend: backend)
      @options.linger = linger
      attach_endpoints(endpoints, default: :connect)
    end
  end


  # Pipeline receiver socket that fair-queues from SCATTER peers (ZeroMQ RFC 49).
  class GATHER < Socket
    include Readable
    include SingleFrame

    # Creates a new GATHER socket.
    #
    # @param endpoints [String, Array<String>, nil] endpoint(s) to bind to
    # @param linger [Numeric] linger period in seconds (Float::INFINITY = wait forever, 0 = drop)
    # @param recv_hwm [Integer, nil] receive high-water mark
    # @param recv_timeout [Integer, nil] receive timeout in seconds
    # @param backend [Object, nil] optional transport backend
    def initialize(endpoints = nil, linger: Float::INFINITY, recv_hwm: nil, recv_timeout: nil, backend: nil)
      init_engine(:GATHER, recv_hwm: recv_hwm, recv_timeout: recv_timeout, backend: backend)
      @options.linger = linger
      attach_endpoints(endpoints, default: :bind)
    end
  end


  Routing.register(:SCATTER, Routing::Scatter)
  Routing.register(:GATHER,  Routing::Gather)
end
