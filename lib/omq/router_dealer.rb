# frozen_string_literal: true

module OMQ
  # DEALER socket — asynchronous round-robin send, fair-queue receive.
  #
  class DEALER < Socket
    include Readable
    include Writable

    # @param endpoints [String, nil] endpoint to bind/connect
    # @param linger [Integer] linger period in seconds
    # @param backend [Symbol, nil] :ruby (default) or :ffi
    #
    def initialize(endpoints = nil, linger: 0, backend: nil)
      _init_engine(:DEALER, linger: linger, backend: backend)
      _attach(endpoints, default: :connect)
    end
  end


  # ROUTER socket.
  #
  class ROUTER < Socket
    include Readable
    include Writable

    # @param endpoints [String, nil] endpoint to bind/connect
    # @param linger [Integer] linger period in seconds
    # @param backend [Symbol, nil] :ruby (default) or :ffi
    #
    def initialize(endpoints = nil, linger: 0, backend: nil)
      _init_engine(:ROUTER, linger: linger, backend: backend)
      _attach(endpoints, default: :bind)
    end


    # Sends a message to a specific peer by identity.
    #
    # @param receiver [String] peer identity
    # @param message [String, Array<String>]
    # @return [self]
    #
    def send_to(receiver, message)
      parts = message.is_a?(Array) ? message : [message]
      send([receiver, '', *parts])
    end
  end
end
