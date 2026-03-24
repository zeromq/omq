# frozen_string_literal: true

$VERBOSE = nil # suppress IO::Buffer experimental warnings

require "minitest/autorun"
require "omq"
require "async"

# Silence Async/Console warnings in tests (e.g. unhandled task exceptions
# that are expected during protocol-error and disconnect tests).
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)
