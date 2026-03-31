# frozen_string_literal: true

module OMQ
  class PUSH < Socket
    include Writable

    def initialize(endpoints = nil, linger: 0, send_hwm: nil, send_timeout: nil)
      _init_engine(:PUSH, linger: linger, send_hwm: send_hwm, send_timeout: send_timeout)
      _attach(endpoints, default: :connect)
    end
  end

  class PULL < Socket
    include Readable

    def initialize(endpoints = nil, linger: 0, recv_hwm: nil, recv_timeout: nil)
      _init_engine(:PULL, linger: linger, recv_hwm: recv_hwm, recv_timeout: recv_timeout)
      _attach(endpoints, default: :bind)
    end
  end
end
