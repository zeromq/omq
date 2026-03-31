# frozen_string_literal: true

module OMQ
  class CHANNEL < Socket
    include Readable
    include Writable
    include SingleFrame

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:CHANNEL, linger: linger)
      _attach(endpoints, default: :connect)
    end
  end
end
