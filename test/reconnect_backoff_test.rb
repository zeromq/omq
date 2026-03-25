# frozen_string_literal: true

require_relative "test_helper"

describe "Reconnection with Range backoff" do
  it "reconnects with exponential backoff" do
    Async do
      # Client connects to a port where nothing is listening yet
      req = OMQ::REQ.new(nil, linger: 0)
      req.reconnect_interval = 0.05..1.0

      rep = OMQ::REP.new(nil, linger: 0)
      rep.bind("tcp://127.0.0.1:0")
      port = rep.last_tcp_port

      # Connect, exchange, then kill the server
      req.connect("tcp://127.0.0.1:#{port}")
      req.send("hello")
      assert_equal ["hello"], rep.receive
      rep.send("world")
      assert_equal ["world"], req.receive

      rep.close

      # Wait for the connection to drop
      sleep 0.1

      # Restart server on same port
      rep2 = OMQ::REP.new(nil, linger: 0)
      rep2.bind("tcp://127.0.0.1:#{port}")

      # Wait for backoff reconnection (starts at 50ms, doubles)
      sleep 0.25

      # Should reconnect and work
      req.send("reconnected")
      msg = rep2.receive
      assert_equal ["reconnected"], msg
    ensure
      req&.close
      rep2&.close
    end
  end

  it "uses fixed interval when reconnect_interval is a number" do
    Async do
      req = OMQ::REQ.new(nil, linger: 0)
      req.reconnect_interval = 0.05

      rep = OMQ::REP.new(nil, linger: 0)
      rep.bind("tcp://127.0.0.1:0")
      port = rep.last_tcp_port

      req.connect("tcp://127.0.0.1:#{port}")
      req.send("first")
      assert_equal ["first"], rep.receive
      rep.send("ok")
      req.receive

      rep.close
      sleep 0.1

      rep2 = OMQ::REP.new(nil, linger: 0)
      rep2.bind("tcp://127.0.0.1:#{port}")
      sleep 0.15

      req.send("second")
      assert_equal ["second"], rep2.receive
    ensure
      req&.close
      rep2&.close
    end
  end
end
