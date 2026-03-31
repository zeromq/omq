# frozen_string_literal: true

module OMQ
  class PAIR < Socket
    include Readable
    include Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:PAIR, linger: linger)
      _attach(endpoints, default: :connect)
    end
  end
end
