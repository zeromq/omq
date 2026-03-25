# frozen_string_literal: true

require_relative "../../lib/omq"
require "async"

prefix = ARGV[0] || ""
label  = prefix.empty? ? "everything" : prefix

Async do
  sub = OMQ::SUB.connect("tcp://localhost:5556")
  sub.subscribe(prefix)
  puts "Subscribed to #{label.inspect} on tcp://5556 ..."

  loop do
    msg = sub.receive
    puts "  #{msg.first}"
  end
ensure
  sub&.close
end
