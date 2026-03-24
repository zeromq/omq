# frozen_string_literal: true

module OMQ
  # REQ socket.
  #
  class REQ < Socket
    include ZMTP::Readable
    include ZMTP::Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:REQ, linger: linger)
      _attach(endpoints, default: :connect)
    end
  end
end
