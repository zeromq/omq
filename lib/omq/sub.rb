# frozen_string_literal: true

module OMQ
  # SUB socket.
  #
  class SUB < Socket
    include ZMTP::Readable

    # @return [String] subscription prefix to subscribe to everything
    #
    EVERYTHING = ''

    # @param endpoints [String, nil]
    # @param linger [Integer]
    # @param prefix [String, nil] subscription prefix; +nil+ (default)
    #   means no subscription — call {#subscribe} explicitly.
    #
    def initialize(endpoints = nil, linger: 0, prefix: nil)
      _init_engine(:SUB, linger: linger)
      _attach(endpoints, default: :connect)
      subscribe(prefix) unless prefix.nil?
    end

    # Subscribes to a topic prefix.
    #
    # @param prefix [String]
    # @return [void]
    #
    def subscribe(prefix = EVERYTHING)
      @engine.routing.subscribe(prefix)
    end

    # Unsubscribes from a topic prefix.
    #
    # @param prefix [String]
    # @return [void]
    #
    def unsubscribe(prefix)
      @engine.routing.unsubscribe(prefix)
    end
  end
end
