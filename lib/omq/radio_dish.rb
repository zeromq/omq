# frozen_string_literal: true

module OMQ
  class RADIO < Socket
    include Writable

    def initialize(endpoints = nil, linger: 0, conflate: false, backend: nil)
      _init_engine(:RADIO, linger: linger, conflate: conflate, backend: backend)
      _attach(endpoints, default: :bind)
    end

    # Publishes a message to a group.
    #
    # @param group [String] group name
    # @param body [String] message body
    # @return [self]
    #
    def publish(group, body)
      with_timeout(@options.write_timeout) do
        @engine.enqueue_send([group.b.freeze, body.b.freeze])
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

  class DISH < Socket
    include Readable

    def initialize(endpoints = nil, linger: 0, group: nil, backend: nil)
      _init_engine(:DISH, linger: linger, backend: backend)
      _attach(endpoints, default: :connect)
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
end
