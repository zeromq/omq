# frozen_string_literal: true

module OMQ
  class DEALER < Socket
    include Readable
    include Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:DEALER, linger: linger)
      _attach(endpoints, default: :connect)
    end
  end

  # ROUTER socket.
  #
  class ROUTER < Socket
    include Readable
    include Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:ROUTER, linger: linger)
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
