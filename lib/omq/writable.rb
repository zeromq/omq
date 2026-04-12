# frozen_string_literal: true

require "timeout"

module OMQ
  # Pure Ruby Writable mixin. Enqueues messages to the engine's send path.
  #
  module Writable
    include QueueWritable
    # Sends a message.
    #
    # @param message [String, Array<String>] message parts
    # @return [self]
    # @raise [IO::TimeoutError] if write_timeout exceeded
    #
    def send(message)
      parts = freeze_message(message)

      Reactor.run timeout: @options.write_timeout do |task|
        @engine.enqueue_send(parts)
      end

      self
    end


    # Sends a message (chainable).
    #
    # @param message [String, Array<String>]
    # @return [self]
    #
    def <<(message)
      send(message)
    end

    private

    # Converts a message into a frozen array of frozen binary strings.
    #
    # @param message [String, Array<String>]
    # @return [Array<String>] frozen array of frozen binary strings
    #
    def freeze_message(message)
      parts = message.is_a?(Array) ? message : [message]
      raise ArgumentError, "message has no parts" if parts.empty?

      # Fast path: skip map when all parts are already frozen binary.
      if parts.frozen?
        return parts if parts.all? { |p| p.is_a?(String) && p.frozen? && p.encoding == Encoding::BINARY }
        parts = parts.map { |p| frozen_binary(p) }
      else
        unless parts.all? { |p| p.is_a?(String) && p.frozen? && p.encoding == Encoding::BINARY }
          parts.map! { |p| frozen_binary(p) }
        end
      end
      parts.freeze
    end


    EMPTY_PART = "".b.freeze

    def frozen_binary(obj)
      return EMPTY_PART if obj.nil?
      s = obj.to_s
      return s if s.frozen? && s.encoding == Encoding::BINARY
      s.b.freeze
    end

    public

    # Waits until the socket is writable.
    #
    # @param timeout [Numeric, nil] timeout in seconds
    # @return [true]
    #
    def wait_writable(timeout = @options.write_timeout)
      true
    end
  end
end
