# frozen_string_literal: true

module OMQ
  # XSUB socket.
  #
  class XSUB < Socket
    include ZMTP::Readable
    include ZMTP::Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:XSUB, linger: linger)
      _attach(endpoints, default: :connect)
    end
  end
end
