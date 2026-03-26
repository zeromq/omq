# frozen_string_literal: true

require_relative "../../lib/omq"
require "async"

endpoint = ARGV[0] || "tcp://*:5557"

Async do
  push = OMQ::PUSH.new(endpoint)
  puts "Ventilator on #{push.last_endpoint} — type tasks, one per line"

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
