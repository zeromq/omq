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
    # @param prefix [String, nil] subscription prefix; defaults to
    #   everything ({EVERYTHING}). Pass +nil+ to skip subscribing.
    #
    def initialize(endpoints = nil, linger: 0, prefix: EVERYTHING)
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
      @engine.instance_variable_get(:@routing).subscribe(prefix)
    end

    # Unsubscribes from a topic prefix.
    #
    # @param prefix [String]
    # @return [void]
    #
    def unsubscribe(prefix)
      @engine.instance_variable_get(:@routing).unsubscribe(prefix)
    end
  end
end
