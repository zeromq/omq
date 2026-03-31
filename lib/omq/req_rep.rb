# frozen_string_literal: true

module OMQ
  class REQ < Socket
    include Readable
    include Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:REQ, linger: linger)
      _attach(endpoints, default: :connect)
    end
  end

  class REP < Socket
    include Readable
    include Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:REP, linger: linger)
      _attach(endpoints, default: :bind)
    end
  end
end
