# frozen_string_literal: true

require_relative "../../lib/omq"
require "async"

endpoint = ARGV[0] || "tcp://*:5555"

Async do
  rep = OMQ::REP.new(endpoint)
  puts "Server on #{rep.last_endpoint} ..."

  loop do
    msg = rep.receive
    puts "  ← #{msg.inspect}"
    rep << msg.map(&:upcase)
  end
ensure
  rep&.close
end
