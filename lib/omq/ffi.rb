# frozen_string_literal: true

# Load the FFI backend for OMQ.
#
# Usage:
#   require "omq/ffi"
#   push = OMQ::PUSH.new(backend: :ffi)
#
# Raises LoadError if libzmq is not installed.

require_relative "ffi/libzmq"
require_relative "ffi/engine"
