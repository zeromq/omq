# frozen_string_literal: true

module OMQ
  class PAIR < Socket
    include Readable
    include Writable

    def initialize(endpoints = nil, linger: 0, backend: nil)
      _init_engine(:PAIR, linger: linger, backend: backend)
      _attach(endpoints, default: :connect)
    end
  end
end
