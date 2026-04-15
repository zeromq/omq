# frozen_string_literal: true

# OMQ side of the interop test. Talks ZMTP to a JeroMQ counterpart.
#
#   ruby omq_side.rb PATTERN ROLE ENDPOINT
#
# PATTERN = push_pull | req_rep | pub_sub
# ROLE    = bind | connect
#   push_pull: binder = PULL, connector = PUSH
#   req_rep:   binder = REP,  connector = REQ
#   pub_sub:   binder = PUB,  connector = SUB
#
# Exits 0 on success, non-zero on mismatch / timeout.

$stdout.sync = true

require "bundler/setup"
require "omq"
require "async"

N       = 100
TIMEOUT = 10.0


def expected_messages = Array.new(N) { "msg-#{it}" }


def push_pull(role, endpoint)
  Sync do
    if role == "bind"
      pull = OMQ::PULL.new(recv_timeout: TIMEOUT)
      pull.bind(endpoint)
      received = N.times.map { pull.receive.first }
      pull.close
      raise "PULL mismatch: #{received.first(3)}" unless received == expected_messages
      puts "OK: OMQ PULL received #{N} messages from JeroMQ PUSH"
    else
      push = OMQ::PUSH.new(linger: 5, send_timeout: TIMEOUT)
      push.connect(endpoint)
      N.times { push << "msg-#{it}" }
      push.close
      puts "OK: OMQ PUSH sent #{N} messages to JeroMQ PULL"
    end
  end
end


def req_rep(role, endpoint)
  Sync do
    if role == "bind"
      rep = OMQ::REP.new(recv_timeout: TIMEOUT, send_timeout: TIMEOUT)
      rep.bind(endpoint)
      N.times do |i|
        req = rep.receive.first
        raise "REP got #{req.inspect}" unless req == "req-#{i}"
        rep << "rep-#{i}"
      end
      rep.close
      puts "OK: OMQ REP answered #{N} requests from JeroMQ REQ"
    else
      req = OMQ::REQ.new(recv_timeout: TIMEOUT, send_timeout: TIMEOUT)
      req.connect(endpoint)
      N.times do |i|
        req << "req-#{i}"
        reply = req.receive.first
        raise "REQ got #{reply.inspect}" unless reply == "rep-#{i}"
      end
      req.close
      puts "OK: OMQ REQ exchanged #{N} req/rep with JeroMQ REP"
    end
  end
end


def pub_sub(role, endpoint)
  Sync do
    if role == "bind"
      pub = OMQ::PUB.new(linger: 5, send_timeout: TIMEOUT)
      pub.bind(endpoint)
      sleep 3.0  # cover JVM cold start + handshake + subscription propagation
      N.times { pub << "topic msg-#{it}" }
      sleep 0.3
      pub.close
      puts "OK: OMQ PUB published #{N} messages to JeroMQ SUB"
    else
      sub = OMQ::SUB.new(subscribe: "topic", recv_timeout: TIMEOUT)
      sub.connect(endpoint)
      received = N.times.map { sub.receive.first }
      sub.close
      raise "SUB mismatch: #{received.first(3)}" unless received == Array.new(N) { "topic msg-#{it}" }
      puts "OK: OMQ SUB received #{N} messages from JeroMQ PUB"
    end
  end
end


pattern, role, endpoint = ARGV
send(pattern, role, endpoint)
