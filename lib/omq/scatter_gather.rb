# frozen_string_literal: true

module OMQ
  class SCATTER < Socket
    include Writable
    include SingleFrame

    def initialize(endpoints = nil, linger: 0, send_hwm: nil, send_timeout: nil, backend: nil)
      _init_engine(:SCATTER, linger: linger, send_hwm: send_hwm, send_timeout: send_timeout, backend: backend)
      _attach(endpoints, default: :connect)
    end
  end

  class GATHER < Socket
    include Readable
    include SingleFrame

    def initialize(endpoints = nil, linger: 0, recv_hwm: nil, recv_timeout: nil, backend: nil)
      _init_engine(:GATHER, linger: linger, recv_hwm: recv_hwm, recv_timeout: recv_timeout, backend: backend)
      _attach(endpoints, default: :bind)
    end
  end
end
