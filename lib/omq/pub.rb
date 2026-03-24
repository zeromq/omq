# frozen_string_literal: true

module OMQ
  # PUB socket.
  #
  class PUB < Socket
    include ZMTP::Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:PUB, linger: linger)
      _attach(endpoints, default: :bind)
    end
  end
end
