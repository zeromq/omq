# frozen_string_literal: true

require_relative "../../lib/omq"
require "async"

endpoint = ARGV[0] || "tcp://*:5556"

Async do
  pub = OMQ::PUB.new(endpoint)
  puts "Publisher on #{pub.last_endpoint} — broadcasting every second ..."

  i = 0
  loop do
    i += 1
    pub << "weather.nyc #{rand(60..100)}F"
    pub << "weather.sfo #{rand(50..80)}F"
    pub << "sports.nba score #{rand(80..120)}-#{rand(80..120)}"
    puts "  broadcast ##{i}"
    sleep 1
  end
ensure
  pub&.close
end
