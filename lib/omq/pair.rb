# frozen_string_literal: true

module OMQ
  # PAIR socket — exclusive 1-to-1 bidirectional communication.
  #
  class PAIR < Socket
    include Readable
    include Writable

    # @param endpoints [String, nil] endpoint to bind/connect
    # @param linger [Integer] linger period in seconds
    # @param backend [Symbol, nil] :ruby (default) or :ffi
    #
    def initialize(endpoints = nil, linger: 0, backend: nil)
      _init_engine(:PAIR, linger: linger, backend: backend)
      _attach(endpoints, default: :connect)
    end
  end
end
