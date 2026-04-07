# frozen_string_literal: true

# OMQ — pure Ruby ZeroMQ (ZMTP 3.1).
#
# Socket types live directly under OMQ:: for a clean API:
#   OMQ::PUSH, OMQ::PULL, OMQ::PUB, OMQ::SUB, etc.
#

require "protocol/zmtp"
require "io/stream"

require_relative "omq/version"
require_relative "omq/monitor_event"

module OMQ
  # When OMQ_DEBUG is set, silent rescue clauses print the exception
  # to stderr so transport/engine bugs surface immediately.
  DEBUG = !!ENV["OMQ_DEBUG"]


  # Raised when an internal pump task crashes unexpectedly.
  # The socket is no longer usable; the original error is available via #cause.
  #
  class SocketDeadError < RuntimeError
  end


  # Errors raised when a peer disconnects or resets the connection.
  # Not frozen at load time — transport plugins append to this before
  # the first bind/connect, which freezes both arrays.
  CONNECTION_LOST = [
    EOFError,
    IOError,
    Errno::EPIPE,
    Errno::ECONNRESET,
    Errno::ECONNABORTED,
    Errno::ENOTCONN,
    IO::Stream::ConnectionResetError,
  ]

  # Errors raised when a peer cannot be reached.
  CONNECTION_FAILED = [
    Errno::ECONNREFUSED,
    Errno::ENOENT,
    Errno::ETIMEDOUT,
    Errno::EHOSTUNREACH,
    Errno::ENETUNREACH,
    Socket::ResolutionError,
  ]
end


# Transport
require_relative "omq/transport/inproc"
require_relative "omq/transport/tcp"
require_relative "omq/transport/ipc"

# Core
require_relative "omq/reactor"
require_relative "omq/options"
require_relative "omq/routing"
require_relative "omq/routing/round_robin"
require_relative "omq/routing/fan_out"
require_relative "omq/routing/pair"
require_relative "omq/routing/req"
require_relative "omq/routing/rep"
require_relative "omq/routing/dealer"
require_relative "omq/routing/router"
require_relative "omq/routing/pub"
require_relative "omq/routing/sub"
require_relative "omq/routing/xpub"
require_relative "omq/routing/xsub"
require_relative "omq/routing/push"
require_relative "omq/routing/pull"
require_relative "omq/engine"
require_relative "omq/queue_interface"
require_relative "omq/readable"
require_relative "omq/writable"
require_relative "omq/single_frame"

# Socket types
require_relative "omq/socket"
require_relative "omq/req_rep"
require_relative "omq/router_dealer"
require_relative "omq/pub_sub"
require_relative "omq/push_pull"
require_relative "omq/pair"

# For the purists.
ØMQ = OMQ
