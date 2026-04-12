# frozen_string_literal: true

module OMQ
  # REQ socket — send a request, then receive one reply (strict alternation).
  #
  class REQ < Socket
    include Readable
    include Writable

    # @param endpoints [String, nil] endpoint to bind/connect
    # @param linger [Integer] linger period in seconds
    # @param backend [Symbol, nil] :ruby (default) or :ffi
    #
    def initialize(endpoints = nil, linger: 0, backend: nil)
      init_engine(:REQ, linger: linger, backend: backend)
      attach_endpoints(endpoints, default: :connect)
    end
  end


  # REP socket — receive a request, then send one reply (strict alternation).
  #
  class REP < Socket
    include Readable
    include Writable

    # @param endpoints [String, nil] endpoint to bind/connect
    # @param linger [Integer] linger period in seconds
    # @param backend [Symbol, nil] :ruby (default) or :ffi
    #
    def initialize(endpoints = nil, linger: 0, backend: nil)
      init_engine(:REP, linger: linger, backend: backend)
      attach_endpoints(endpoints, default: :bind)
    end
  end
end
