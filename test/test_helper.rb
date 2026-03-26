# frozen_string_literal: true

require "minitest/autorun"
require "omq"
require "async"

# Silence Async/Console warnings in tests (e.g. unhandled task exceptions
# that are expected during protocol-error and disconnect tests).
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)
