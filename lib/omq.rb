# frozen_string_literal: true

# OMQ — pure Ruby ZeroMQ (ZMTP 3.1).
#
# Socket types live directly under OMQ:: for a clean API:
#   OMQ::PUSH, OMQ::PULL, OMQ::PUB, OMQ::SUB, etc.
#
# Protocol internals live under OMQ::ZMTP:: and are not part
# of the public API.
#
module OMQ
  VERSION = "0.1.0"
end

require_relative "omq/zmtp"
require_relative "omq/socket"

# Simple socket types defined via Socket.define
module OMQ
  REQ    = Socket.define(:REQ,    :connect, readable: true, writable: true)
  REP    = Socket.define(:REP,    :bind,    readable: true, writable: true)
  DEALER = Socket.define(:DEALER, :connect, readable: true, writable: true)
  PUB    = Socket.define(:PUB,    :bind,    writable: true)
  XPUB   = Socket.define(:XPUB,   :bind,    readable: true, writable: true)
  XSUB   = Socket.define(:XSUB,   :connect, readable: true, writable: true)
  PUSH   = Socket.define(:PUSH,   :connect, writable: true)
  PULL   = Socket.define(:PULL,   :bind,    readable: true)
  PAIR   = Socket.define(:PAIR,   :connect, readable: true, writable: true)
end

# Socket types with extra methods
require_relative "omq/router"
require_relative "omq/sub"
