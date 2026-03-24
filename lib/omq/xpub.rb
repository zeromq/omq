# frozen_string_literal: true

module OMQ
  # XPUB socket.
  #
  class XPUB < Socket
    include ZMTP::Readable
    include ZMTP::Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:XPUB, linger: linger)
      _attach(endpoints, default: :bind)
    end
  end
end
