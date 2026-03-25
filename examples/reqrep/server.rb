# frozen_string_literal: true

require_relative "../lib/omq"
require "async"

Async do
  rep = OMQ::REP.bind("tcp://*:5555")
  puts "Server listening on tcp://5555 ..."

  loop do
    msg = rep.receive
    puts "  ← #{msg.inspect}"
    rep << msg.map(&:upcase)
  end
ensure
  rep&.close
end
