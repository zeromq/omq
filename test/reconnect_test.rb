# frozen_string_literal: true

require_relative "test_helper"

describe "Auto-reconnection" do
  it "reconnects after server restart over TCP" do
    Async do
      # Start server
      rep = OMQ::REP.new(nil, linger: 0)
      rep.bind("tcp://127.0.0.1:0")
      port = rep.last_tcp_port

      # Client connects
      req = OMQ::REQ.new(nil, linger: 0)
      req.connect("tcp://127.0.0.1:#{port}")

      # First exchange works
      req.send("hello")
      msg = rep.receive
      assert_equal ["hello"], msg
      rep.send("world")
      reply = req.receive
      assert_equal ["world"], reply

      # Kill the server
      rep.close

      # Wait a bit for the reconnect to kick in
      sleep 0.3

      # Restart server on same port
      rep2 = OMQ::REP.new(nil, linger: 0)
      rep2.bind("tcp://127.0.0.1:#{port}")

      # Wait for reconnection
      sleep 0.5

      # Second exchange should work after reconnection
      req.send("reconnected")
      msg = rep2.receive
      assert_equal ["reconnected"], msg
      rep2.send("yes")
      reply = req.receive
      assert_equal ["yes"], reply
    ensure
      req&.close
      rep2&.close
    end
  end
end
