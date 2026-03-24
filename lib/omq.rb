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
require_relative "omq/pair"
require_relative "omq/req"
require_relative "omq/rep"
require_relative "omq/dealer"
require_relative "omq/router"
require_relative "omq/pub"
require_relative "omq/sub"
require_relative "omq/xpub"
require_relative "omq/xsub"
require_relative "omq/push"
require_relative "omq/pull"
