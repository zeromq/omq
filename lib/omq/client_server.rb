# frozen_string_literal: true

module OMQ
  class CLIENT < Socket
    include Readable
    include Writable
    include SingleFrame

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:CLIENT, linger: linger)
      _attach(endpoints, default: :connect)
    end
  end

  class SERVER < Socket
    include Readable
    include Writable
    include SingleFrame

    def initialize(endpoints = nil, linger: 0)
      _init_engine(:SERVER, linger: linger)
      _attach(endpoints, default: :bind)
    end

    # Sends a message to a specific peer by routing ID.
    #
    # @param routing_id [String] 4-byte routing ID
    # @param message [String] message body
    # @return [self]
    #
    def send_to(routing_id, message)
      parts = [routing_id.b.freeze, message.b.freeze]
      with_timeout(@options.write_timeout) { @engine.enqueue_send(parts) }
      self
    end
  end
end
