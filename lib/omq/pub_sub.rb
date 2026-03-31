# frozen_string_literal: true

module OMQ
  class PUB < Socket
    include Writable

    def initialize(endpoints = nil, linger: 0, conflate: false)
      _init_engine(:PUB, linger: linger, conflate: conflate)
      _attach(endpoints, default: :bind)
    end
  end

  # SUB socket.
  #
  class SUB < Socket
    include Readable

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

  class XPUB < Socket
    include Readable
    include Writable

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:XPUB, linger: linger)
      _attach(endpoints, default: :bind)
    end
  end

  class XSUB < Socket
    include Readable
    include Writable

    # @param endpoints [String, nil]
    # @param linger [Integer]
    # @param prefix [String, nil] subscription prefix; +nil+ (default)
    #   means no subscription — send a subscribe frame explicitly.
    #
    def initialize(endpoints = nil, linger: 0, prefix: nil)
      _init_engine(:XSUB, linger: linger)
      _attach(endpoints, default: :connect)
      send("\x01#{prefix}".b) unless prefix.nil?
    end
  end
end
