# frozen_string_literal: true

module OMQ
  module ZMTP
    # ZMTP 3.1 wire protocol codec.
    #
    module Codec
    end

    # Raised on ZMTP protocol violations.
    #
    class ProtocolError < RuntimeError; end
  end
end

require_relative "codec/greeting"
require_relative "codec/frame"
require_relative "codec/command"
