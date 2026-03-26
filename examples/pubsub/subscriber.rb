# frozen_string_literal: true

require_relative "../../lib/omq"
require "async"

endpoint = ARGV[0] || "tcp://localhost:5556"
prefix   = ARGV[1] || ""

Async do
  sub = OMQ::SUB.new(endpoint, prefix: prefix)
  label = prefix.empty? ? "#{prefix.inspect} (everything)" : prefix.inspect
  puts "Subscribed to #{label} on #{endpoint.delete_prefix(">")} ..."

  loop do
    msg = sub.receive
    puts "  #{msg.first}"
  end
ensure
  sub&.close
end
