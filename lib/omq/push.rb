# frozen_string_literal: true

module OMQ
  # PUSH socket.
  #
  class PUSH < Socket
    include ZMTP::Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:PUSH, linger: linger)
      _attach(endpoints, default: :connect)
    end
  end
end
