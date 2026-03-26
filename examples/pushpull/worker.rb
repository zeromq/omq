# frozen_string_literal: true

require_relative "../../lib/omq"
require "async"

endpoint = ARGV[0] || "tcp://localhost:5557"
id       = ARGV[1] || $$

Async do
  pull = OMQ::PULL.new(endpoint)
  puts "Worker #{id} connected to #{endpoint.delete_prefix(">")} — waiting for tasks ..."

  loop do
    msg = pull.receive
    puts "  [#{id}] got: #{msg.inspect}"
  end
ensure
  pull&.close
end
