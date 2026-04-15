# frozen_string_literal: true

# JeroMQ side of the interop test. Talks ZMTP to an OMQ counterpart.
#
#   jruby jeromq_side.rb PATTERN ROLE ENDPOINT
#
# Mirrors omq_side.rb.

$stdout.sync = true

raise "this script requires JRuby" unless RUBY_PLATFORM == "java"

require "java"
require_relative "../vendor/jeromq-0.6.0.jar"

java_import "org.zeromq.ZContext"
java_import "org.zeromq.SocketType"

N          = 100
TIMEOUT_MS = 10_000


def expected_messages = Array.new(N) { "msg-#{it}" }


def recv_str(sock)
  bytes = sock.recv(0)
  raise "timeout / disconnected" if bytes.nil?
  String.from_java_bytes(bytes).force_encoding("UTF-8")
end


def send_str(sock, str)
  sock.send(str.to_java_bytes, 0)
end


def with_timeouts(sock)
  sock.setReceiveTimeOut(TIMEOUT_MS)
  sock.setSendTimeOut(TIMEOUT_MS)
  sock
end


def push_pull(ctx, role, endpoint)
  if role == "bind"
    pull = with_timeouts(ctx.createSocket(SocketType::PULL))
    pull.bind(endpoint)
    received = N.times.map { recv_str(pull) }
    ctx.destroySocket(pull)
    raise "PULL mismatch: #{received.first(3)}" unless received == expected_messages
    puts "OK: JeroMQ PULL received #{N} messages from OMQ PUSH"
  else
    push = with_timeouts(ctx.createSocket(SocketType::PUSH))
    push.setLinger(500)
    push.connect(endpoint)
    N.times { |i| send_str(push, "msg-#{i}") }
    sleep 0.2
    ctx.destroySocket(push)
    puts "OK: JeroMQ PUSH sent #{N} messages to OMQ PULL"
  end
end


def req_rep(ctx, role, endpoint)
  if role == "bind"
    rep = with_timeouts(ctx.createSocket(SocketType::REP))
    rep.bind(endpoint)
    N.times do |i|
      req = recv_str(rep)
      raise "REP got #{req.inspect}" unless req == "req-#{i}"
      send_str(rep, "rep-#{i}")
    end
    ctx.destroySocket(rep)
    puts "OK: JeroMQ REP answered #{N} requests from OMQ REQ"
  else
    req = with_timeouts(ctx.createSocket(SocketType::REQ))
    req.connect(endpoint)
    N.times do |i|
      send_str(req, "req-#{i}")
      reply = recv_str(req)
      raise "REQ got #{reply.inspect}" unless reply == "rep-#{i}"
    end
    ctx.destroySocket(req)
    puts "OK: JeroMQ REQ exchanged #{N} req/rep with OMQ REP"
  end
end


def pub_sub(ctx, role, endpoint)
  if role == "bind"
    pub = with_timeouts(ctx.createSocket(SocketType::PUB))
    pub.setLinger(500)
    pub.bind(endpoint)
    sleep 3.0
    N.times { |i| send_str(pub, "topic msg-#{i}") }
    sleep 0.3
    ctx.destroySocket(pub)
    puts "OK: JeroMQ PUB published #{N} messages to OMQ SUB"
  else
    sub = with_timeouts(ctx.createSocket(SocketType::SUB))
    sub.connect(endpoint)
    sub.subscribe("topic".to_java_bytes)
    received = N.times.map { recv_str(sub) }
    ctx.destroySocket(sub)
    raise "SUB mismatch: #{received.first(3)}" unless received == Array.new(N) { |i| "topic msg-#{i}" }
    puts "OK: JeroMQ SUB received #{N} messages from OMQ PUB"
  end
end


pattern, role, endpoint = ARGV
ctx = ZContext.new
begin
  send(pattern, ctx, role, endpoint)
ensure
  ctx.close
end
