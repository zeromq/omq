# frozen_string_literal: true

module OMQ
  # ROUTER socket.
  #
  class ROUTER < Socket
    include ZMTP::Readable
    include ZMTP::Writable

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
