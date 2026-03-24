# frozen_string_literal: true

require_relative "test_helper"

describe "max_message_size" do
  it "rejects oversized frames over TCP" do
    Async do
      rep = OMQ::REP.new(nil, linger: 0)
      rep.max_message_size = 10
      rep.bind("tcp://127.0.0.1:0")
      port = rep.last_tcp_port

      req = OMQ::REQ.new(nil, linger: 0)
      req.connect("tcp://127.0.0.1:#{port}")

      # Small message — should work
      req.send("hi")
      msg = rep.receive
      assert_equal ["hi"], msg
      rep.send("ok")
      req.receive

      # Oversized message — connection should be closed
      req.send("x" * 100)

      # REP should not receive it (connection closed)
      rep.read_timeout = 0.5
      assert_raises(IO::TimeoutError) { rep.receive }
    ensure
      req&.close
      rep&.close
    end
  end

  it "allows messages within limit" do
    Async do
      rep = OMQ::REP.new(nil, linger: 0)
      rep.max_message_size = 1024
      rep.bind("tcp://127.0.0.1:0")
      port = rep.last_tcp_port

      req = OMQ::REQ.new(nil, linger: 0)
      req.connect("tcp://127.0.0.1:#{port}")

      req.send("x" * 500)
      msg = rep.receive
      assert_equal 500, msg.first.bytesize
    ensure
      req&.close
      rep&.close
    end
  end

  it "has no limit by default" do
    Async do
      rep = OMQ::REP.new(nil, linger: 0)
      rep.bind("tcp://127.0.0.1:0")
      port = rep.last_tcp_port

      req = OMQ::REQ.new(nil, linger: 0)
      req.connect("tcp://127.0.0.1:#{port}")

      big = "x" * 100_000
      req.send(big)
      msg = rep.receive
      assert_equal 100_000, msg.first.bytesize
    ensure
      req&.close
      rep&.close
    end
  end
end
