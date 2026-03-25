# frozen_string_literal: true

require_relative "../lib/omq"
require "async"

Async do
  req = OMQ::REQ.connect("tcp://localhost:5555")
  puts "Client connected to tcp://5555"

  loop do
    print "> "
    input = $stdin.gets&.chomp
    break if input.nil? || input.empty?

    req << input
    reply = req.receive
    puts "  → #{reply.inspect}"
  end
ensure
  req&.close
end
