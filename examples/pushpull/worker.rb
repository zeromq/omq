# frozen_string_literal: true

require_relative "../../lib/omq"
require "async"

id = ARGV[0] || $$

Async do
  pull = OMQ::PULL.connect("tcp://localhost:5557")
  puts "Worker #{id} connected — waiting for tasks ..."

  loop do
    msg = pull.receive
    puts "  [#{id}] got: #{msg.inspect}"
  end
ensure
  pull&.close
end
