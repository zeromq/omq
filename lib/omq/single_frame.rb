# frozen_string_literal: true

module OMQ
  # Mixin that rejects multipart messages.
  #
  # All draft socket types (CLIENT, SERVER, RADIO, DISH, SCATTER,
  # GATHER, PEER, CHANNEL) require single-frame messages for
  # thread-safe atomic operations.
  #
  module SingleFrame
    def send(message)
      if message.is_a?(Array) && message.size > 1
        raise ArgumentError, "#{self.class} does not support multipart messages"
      end
      super
    end
  end
end
