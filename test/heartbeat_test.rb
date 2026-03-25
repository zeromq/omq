# frozen_string_literal: true

require_relative "test_helper"

describe "Heartbeat" do
  it "sends PING and receives PONG over TCP" do
    Async do
      rep = OMQ::REP.new(nil, linger: 0)
      rep.heartbeat_interval = 0.1
      rep.heartbeat_ttl = 1.0
      rep.bind("tcp://127.0.0.1:0")
      port = rep.last_tcp_port

      req = OMQ::REQ.new(nil, linger: 0)
      req.heartbeat_interval = 0.1
      req.heartbeat_ttl = 1.0
      req.connect("tcp://127.0.0.1:#{port}")

      # Exchange a message (heartbeats run in background)
      req.send("hello")
      msg = rep.receive
      assert_equal ["hello"], msg

      rep.send("world")
      reply = req.receive
      assert_equal ["world"], reply

      # Wait — heartbeats should keep the connection alive
      sleep 0.15

      # Another exchange should still work
      req.send("still alive")
      msg = rep.receive
      assert_equal ["still alive"], msg

      rep.send("yes")
      reply = req.receive
      assert_equal ["yes"], reply
    ensure
      req&.close
      rep&.close
    end
  end

  it "detects dead peer via heartbeat timeout" do
    Async do
      rep = OMQ::REP.new(nil, linger: 0)
      rep.heartbeat_interval     = 0.05
      rep.heartbeat_timeout = 0.15
      rep.bind("tcp://127.0.0.1:0")
      port = rep.last_tcp_port

      req = OMQ::REQ.new(nil, linger: 0)
      req.connect("tcp://127.0.0.1:#{port}")

      # Exchange one message
      req.send("ping")
      msg = rep.receive
      assert_equal ["ping"], msg
      rep.send("pong")
      req.receive

      # Close the REQ side abruptly (simulating dead peer)
      req.close

      # Wait for heartbeat timeout to detect the dead peer
      sleep 0.2

      # REP should have detected dead peer. Try to receive — should timeout.
      rep.recv_timeout = 0.1
      assert_raises(IO::TimeoutError) { rep.receive }
    ensure
      rep&.close
    end
  end
end
