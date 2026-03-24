# frozen_string_literal: true

module OMQ
  # PULL socket.
  #
  class PULL < Socket
    include ZMTP::Readable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:PULL, linger: linger)
      _attach(endpoints, default: :bind)
    end
  end
end
