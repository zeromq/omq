# frozen_string_literal: true

module OMQ
  # PUSH socket — push messages to connected PULL peers via round-robin.
  #
  class PUSH < Socket
    include Writable

    # @param endpoints [String, nil] endpoint to bind/connect
    # @param linger [Integer] linger period in seconds
    # @param send_hwm [Integer, nil] send high water mark (nil uses default)
    # @param send_timeout [Numeric, nil] send timeout in seconds
    # @param backend [Symbol, nil] :ruby (default) or :ffi
    #
    def initialize(endpoints = nil, linger: 0, send_hwm: nil, send_timeout: nil, backend: nil)
      _init_engine(:PUSH, linger: linger, send_hwm: send_hwm, send_timeout: send_timeout, backend: backend)
      _attach(endpoints, default: :connect)
    end
  end


  # PULL socket — receive messages from PUSH peers via fair-queue.
  #
  class PULL < Socket
    include Readable

    # @param endpoints [String, nil] endpoint to bind/connect
    # @param linger [Integer] linger period in seconds
    # @param recv_hwm [Integer, nil] receive high water mark (nil uses default)
    # @param recv_timeout [Numeric, nil] receive timeout in seconds
    # @param backend [Symbol, nil] :ruby (default) or :ffi
    #
    def initialize(endpoints = nil, linger: 0, recv_hwm: nil, recv_timeout: nil, backend: nil)
      _init_engine(:PULL, linger: linger, recv_hwm: recv_hwm, recv_timeout: recv_timeout, backend: backend)
      _attach(endpoints, default: :bind)
    end
  end
end
