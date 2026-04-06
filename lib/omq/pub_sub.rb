# frozen_string_literal: true

module OMQ
  # PUB socket — publish messages to all matching subscribers.
  #
  class PUB < Socket
    include Writable

    # @param endpoints [String, nil] endpoint to bind/connect
    # @param linger [Integer] linger period in seconds
    # @param on_mute [Symbol] mute strategy for slow subscribers
    # @param conflate [Boolean] keep only latest message per topic
    # @param backend [Symbol, nil] :ruby (default) or :ffi
    #
    def initialize(endpoints = nil, linger: 0, on_mute: :drop_newest, conflate: false, backend: nil)
      _init_engine(:PUB, linger: linger, on_mute: on_mute, conflate: conflate, backend: backend)
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
    # @param subscribe [String, nil] subscription prefix; +nil+ (default)
    #   means no subscription — call {#subscribe} explicitly.
    # @param on_mute [Symbol] :block (default), :drop_newest, or :drop_oldest
    #
    def initialize(endpoints = nil, linger: 0, subscribe: nil, on_mute: :block, backend: nil)
      _init_engine(:SUB, linger: linger, on_mute: on_mute, backend: backend)
      _attach(endpoints, default: :connect)
      self.subscribe(subscribe) unless subscribe.nil?
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


  # XPUB socket — like PUB but exposes subscription events to the application.
  #
  class XPUB < Socket
    include Readable
    include Writable

    # @param endpoints [String, nil] endpoint to bind/connect
    # @param linger [Integer] linger period in seconds
    # @param on_mute [Symbol] mute strategy for slow subscribers
    # @param backend [Symbol, nil] :ruby (default) or :ffi
    #
    def initialize(endpoints = nil, linger: 0, on_mute: :drop_newest, backend: nil)
      _init_engine(:XPUB, linger: linger, on_mute: on_mute, backend: backend)
      _attach(endpoints, default: :bind)
    end
  end


  # XSUB socket — like SUB but subscriptions are sent as data frames.
  #
  class XSUB < Socket
    include Readable
    include Writable

    # @param endpoints [String, nil]
    # @param linger [Integer]
    # @param subscribe [String, nil] subscription prefix; +nil+ (default)
    #   means no subscription — send a subscribe frame explicitly.
    # @param on_mute [Symbol] mute strategy (:block, :drop_newest, :drop_oldest)
    # @param backend [Symbol, nil] :ruby (default) or :ffi
    #
    def initialize(endpoints = nil, linger: 0, subscribe: nil, on_mute: :block, backend: nil)
      _init_engine(:XSUB, linger: linger, on_mute: on_mute, backend: backend)
      _attach(endpoints, default: :connect)
      send("\x01#{subscribe}".b) unless subscribe.nil?
    end
  end
end
