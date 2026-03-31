# frozen_string_literal: true

require "protocol/zmtp"
require "io/stream"

module OMQ
  # ZMTP 3.1 protocol internals.
  #
  # The wire protocol (codec, connection, mechanisms) lives in the
  # protocol-zmtp gem. This module re-exports those classes under the
  # OMQ::ZMTP namespace and adds the transport/routing/engine layers.
  #
  module ZMTP
    # Re-export protocol-zmtp classes
    Codec         = Protocol::ZMTP::Codec
    Connection    = Protocol::ZMTP::Connection
    ProtocolError = Protocol::ZMTP::Error
    VALID_PEERS   = Protocol::ZMTP::VALID_PEERS

    module Mechanism
      Null  = Protocol::ZMTP::Mechanism::Null
      Curve = Protocol::ZMTP::Mechanism::Curve if defined?(Protocol::ZMTP::Mechanism::Curve)
    end

    # Errors raised when a peer disconnects or resets the connection.
    CONNECTION_LOST = [
      EOFError,
      IOError,
      Errno::EPIPE,
      Errno::ECONNRESET,
      Errno::ECONNABORTED,
      Errno::ENOTCONN,
      IO::Stream::ConnectionResetError,
    ].freeze

    # Errors raised when a peer cannot be reached.
    CONNECTION_FAILED = [
      Errno::ECONNREFUSED,
      Errno::ENOENT,
      Errno::ETIMEDOUT,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Socket::ResolutionError,
    ].freeze
  end
end

# Transport
require_relative "zmtp/transport/inproc"
require_relative "zmtp/transport/tcp"
require_relative "zmtp/transport/ipc"

# Core
require_relative "zmtp/reactor"
require_relative "zmtp/options"
require_relative "zmtp/routing"
require_relative "zmtp/routing/round_robin"
require_relative "zmtp/routing/fan_out"
require_relative "zmtp/routing/pair"
require_relative "zmtp/routing/req"
require_relative "zmtp/routing/rep"
require_relative "zmtp/routing/dealer"
require_relative "zmtp/routing/router"
require_relative "zmtp/routing/pub"
require_relative "zmtp/routing/sub"
require_relative "zmtp/routing/xpub"
require_relative "zmtp/routing/xsub"
require_relative "zmtp/routing/push"
require_relative "zmtp/routing/pull"
require_relative "zmtp/routing/scatter"
require_relative "zmtp/routing/gather"
require_relative "zmtp/routing/channel"
require_relative "zmtp/routing/client"
require_relative "zmtp/routing/server"
require_relative "zmtp/routing/radio"
require_relative "zmtp/routing/dish"
require_relative "zmtp/routing/peer"
require_relative "zmtp/single_frame"
require_relative "zmtp/engine"
require_relative "zmtp/readable"
require_relative "zmtp/writable"
