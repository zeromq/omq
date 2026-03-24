# frozen_string_literal: true

module OMQ
  # PAIR socket.
  #
  class PAIR < Socket
    include ZMTP::Readable
    include ZMTP::Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:PAIR, linger: linger)
      _attach(endpoints, default: :connect)
    end
  end
end
