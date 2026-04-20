# frozen_string_literal: true

# Profile the PUSH/PULL hot path with stackprof.
#
# Usage:
#   bundle exec ruby --yjit bench/profile_push_pull.rb [inproc|ipc] [cpu|wall] [msg_size] [msg_count]
#
# Defaults: inproc, cpu, 512, 1_000_000
#
# Writes a dump at /tmp/omq-profile-<transport>-<mode>-<size>b.dump and
# prints the top frames by self-time.

$VERBOSE = nil
$stdout.sync = true

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "omq", path: File.expand_path("..", __dir__)
  gem "stackprof"
end

require "stackprof"
require "omq"
require "async"
require "console"
Console.logger = Console::Logger.new(Console::Output::Null.new)

transport = (ARGV[0] || "inproc")
mode      = (ARGV[1] || "cpu").to_sym
msg_size  = Integer(ARGV[2] || 512)
msg_count = Integer(ARGV[3] || 1_000_000)

endpoint = case transport
when "inproc" then "inproc://profile"
when "ipc"    then "ipc://@omq-profile"
else abort "unsupported transport: #{transport}"
end

payload = "x" * msg_size
dump    = "/tmp/omq-profile-#{transport}-#{mode}-#{msg_size}b.dump"

puts "profiling PUSH/PULL | transport=#{transport} mode=#{mode} size=#{msg_size}B n=#{msg_count}"

Async do |task|
  pull = OMQ::PULL.new
  pull.bind(endpoint)
  push = OMQ::PUSH.new
  push.connect(endpoint)
  push.peer_connected.wait unless transport == "inproc"

  # Prime: shake out YJIT compile and fiber stack setup. Sender must run
  # on a separate fiber so it can yield when the HWM blocks it.
  task.async { 5_000.times { push << payload } }
  5_000.times { pull.receive }

  t0 = Async::Clock.now

  StackProf.run(mode: mode, out: dump, raw: true, interval: 1_000) do
    sender = task.async do
      msg_count.times { push << payload }
    end

    msg_count.times { pull.receive }
    sender.wait
  end

  elapsed = Async::Clock.now - t0
  rate    = msg_count / elapsed
  puts "elapsed=#{elapsed.round(3)}s rate=#{rate.round} msg/s"

  push.close
  pull.close
end

puts "dump: #{dump}"
puts
puts "--- top self-time (25) ---"
report = StackProf::Report.new(Marshal.load(File.binread(dump)))
report.print_text(false, 25)
