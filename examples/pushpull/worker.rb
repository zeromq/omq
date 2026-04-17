# frozen_string_literal: true

require_relative "../../lib/omq"
require "async"

endpoint = ARGV[0] || "tcp://*:5557"
id       = ARGV[1] || $$

Async do
  pull = OMQ::PULL.new
  where = endpoint.start_with?(">") ? pull.connect(endpoint.delete_prefix(">")) : pull.bind(endpoint)
  puts "Worker #{id} on #{where} — waiting for tasks ..."

  loop do
    msg = pull.receive
    puts "  [#{id}] got: #{msg.inspect}"
  end
ensure
  pull&.close
end
