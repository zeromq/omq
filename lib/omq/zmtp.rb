# frozen_string_literal: true

module OMQ
  # ZMTP 3.1 protocol internals.
  #
  # These classes implement the wire protocol, transports, and routing
  # strategies. They are not part of the public API.
  #
  module ZMTP
  end
end

# Constants
require_relative "zmtp/valid_peers"

# Codec
require_relative "zmtp/codec"

# Transport
require_relative "zmtp/transport/inproc"
require_relative "zmtp/transport/tcp"
require_relative "zmtp/transport/ipc"

# Core
require_relative "zmtp/reactor"
require_relative "zmtp/options"
require_relative "zmtp/connection"
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
require_relative "zmtp/engine"
require_relative "zmtp/readable"
require_relative "zmtp/writable"
