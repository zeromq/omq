# frozen_string_literal: true

require_relative "../../lib/omq"
require "async"

endpoint = ARGV[0] || "tcp://localhost:5555"

Async do
  req = OMQ::REQ.new(endpoint)
  puts "Client connected to #{endpoint.delete_prefix(">")}"

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
