# frozen_string_literal: true

module OMQ
  # DEALER socket.
  #
  class DEALER < Socket
    include ZMTP::Readable
    include ZMTP::Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:DEALER, linger: linger)
      _attach(endpoints, default: :connect)
    end
  end
end
