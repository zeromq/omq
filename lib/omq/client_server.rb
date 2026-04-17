# frozen_string_literal: true

# OMQ CLIENT/SERVER socket types (ZeroMQ RFC 41).
#
# Not loaded by +require "omq"+; opt in with:
#
#   require "omq/client_server"

require "omq"
require_relative "routing/client"
require_relative "routing/server"

module OMQ
  # Asynchronous client socket for the CLIENT/SERVER pattern (ZeroMQ RFC 41).
  #
  # Round-robins outgoing messages across connected SERVER peers.
  class CLIENT < Socket
    include Readable
    include Writable
    include SingleFrame

    # Creates a new CLIENT socket.
    #
    # @param endpoints [String, Array<String>, nil] endpoint(s) to connect to
    # @param linger [Numeric] linger period in seconds (Float::INFINITY = wait forever, 0 = drop)
    # @param backend [Object, nil] optional transport backend
    def initialize(endpoints = nil, linger: Float::INFINITY, backend: nil)
      init_engine(:CLIENT, backend: backend)
      @options.linger = linger
      attach_endpoints(endpoints, default: :connect)
    end
  end


  # Asynchronous server socket for the CLIENT/SERVER pattern (ZeroMQ RFC 41).
  #
  # Assigns a 4-byte routing ID to each connected CLIENT and supports
  # directed replies via #send_to.
  class SERVER < Socket
    include Readable
    include Writable
    include SingleFrame

    # Creates a new SERVER socket.
    #
    # @param endpoints [String, Array<String>, nil] endpoint(s) to bind to
    # @param linger [Numeric] linger period in seconds (Float::INFINITY = wait forever, 0 = drop)
    # @param backend [Object, nil] optional transport backend
    def initialize(endpoints = nil, linger: Float::INFINITY, backend: nil)
      init_engine(:SERVER, backend: backend)
      @options.linger = linger
      attach_endpoints(endpoints, default: :bind)
    end


    # Sends a message to a specific peer by routing ID.
    #
    # @param routing_id [String] 4-byte routing ID
    # @param message [String] message body
    # @return [self]
    #
    def send_to(routing_id, message)
      parts = [routing_id.b.freeze, message.b.freeze]
      Reactor.run(timeout: @options.write_timeout) { @engine.enqueue_send(parts) }
      self
    end
  end


  Routing.register(:CLIENT, Routing::Client)
  Routing.register(:SERVER, Routing::Server)
end
