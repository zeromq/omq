# frozen_string_literal: true

# OMQ RADIO/DISH socket types with UDP transport (ZeroMQ RFC 48).
#
# Not loaded by +require "omq"+; opt in with:
#
#   require "omq/radio_dish"
#
# Loading this file also registers the +udp://+ transport.

require "omq"
require_relative "routing/radio"
require_relative "routing/dish"
require_relative "transport/udp"

module OMQ
  # Group-based publisher socket (ZeroMQ RFC 48).
  #
  # Sends messages to DISH peers that have joined the target group.
  # Supports both TCP and UDP transports.
  class RADIO < Socket
    include Writable

    # Creates a new RADIO socket.
    #
    # @param endpoints [String, Array<String>, nil] endpoint(s) to bind to
    # @param linger [Numeric] linger period in seconds (Float::INFINITY = wait forever, 0 = drop)
    # @param on_mute [Symbol] behaviour when HWM is reached (+:drop_newest+ or +:block+)
    # @param conflate [Boolean] if true, keep only the latest message per group per peer
    # @param backend [Object, nil] optional transport backend
    def initialize(endpoints = nil, linger: Float::INFINITY, on_mute: :drop_newest, conflate: false, backend: nil)
      init_engine(:RADIO, on_mute: on_mute, conflate: conflate, backend: backend)
      @options.linger = linger
      attach_endpoints(endpoints, default: :bind)
    end


    # Publishes a message to a group.
    #
    # @param group [String] group name
    # @param body [String] message body
    # @return [self]
    #
    def publish(group, body)
      parts = [group.b.freeze, body.b.freeze]
      Reactor.run timeout: @options.write_timeout do
        @engine.enqueue_send(parts)
      end
      self
    end


    # Sends a message to a group.
    #
    # @param message [String] message body (requires group: kwarg)
    # @param group [String] group name
    # @return [self]
    #
    def send(message, group: nil)
      raise ArgumentError, "RADIO requires a group (use group: kwarg, publish, or << [group, body])" unless group
      publish(group, message)
    end


    # Sends a message to a group via [group, body] array.
    #
    # @param message [Array<String>] [group, body]
    # @return [self]
    #
    def <<(message)
      raise ArgumentError, "RADIO requires [group, body] array" unless message.is_a?(Array) && message.size == 2
      publish(message[0], message[1])
    end
  end


  # Group-based subscriber socket (ZeroMQ RFC 48).
  #
  # Receives messages from RADIO peers for joined groups.
  # Supports both TCP and UDP transports.
  class DISH < Socket
    include Readable

    # Creates a new DISH socket.
    #
    # @param endpoints [String, Array<String>, nil] endpoint(s) to connect to
    # @param linger [Numeric] linger period in seconds (Float::INFINITY = wait forever, 0 = drop)
    # @param group [String, nil] initial group to join
    # @param on_mute [Symbol] behaviour when HWM is reached (+:block+ or +:drop_newest+)
    # @param backend [Object, nil] optional transport backend
    def initialize(endpoints = nil, linger: Float::INFINITY, group: nil, on_mute: :block, backend: nil)
      init_engine(:DISH, on_mute: on_mute, backend: backend)
      @options.linger = linger
      attach_endpoints(endpoints, default: :connect)
      join(group) if group
    end


    # Joins a group.
    #
    # @param group [String]
    # @return [void]
    #
    def join(group)
      @engine.routing.join(group)
    end


    # Leaves a group.
    #
    # @param group [String]
    # @return [void]
    #
    def leave(group)
      @engine.routing.leave(group)
    end
  end


  Routing.register(:RADIO, Routing::Radio)
  Routing.register(:DISH,  Routing::Dish)
end
