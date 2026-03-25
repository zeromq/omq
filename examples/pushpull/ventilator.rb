# frozen_string_literal: true

require_relative "../../lib/omq"
require "async"

Async do
  push = OMQ::PUSH.bind("tcp://*:5557")
  puts "Ventilator bound on tcp://5557 — type tasks, one per line"

  loop do
    print "> "
    input = $stdin.gets&.chomp
    break if input.nil? || input.empty?

    push << input
    puts "  sent"
  end
ensure
  push&.close
end
