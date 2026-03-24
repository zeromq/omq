# frozen_string_literal: true

module OMQ
  # REP socket.
  #
  class REP < Socket
    include ZMTP::Readable
    include ZMTP::Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:REP, linger: linger)
      _attach(endpoints, default: :bind)
    end
  end
end
