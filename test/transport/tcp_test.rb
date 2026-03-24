# frozen_string_literal: true

require_relative "../test_helper"

describe "TCP transport" do
  it "PAIR over TCP with ephemeral port" do
    Async do
      server = OMQ::PAIR.bind("tcp://127.0.0.1:0")
      port = server.last_tcp_port
      refute_nil port
      assert port > 0

      client = OMQ::PAIR.connect("tcp://127.0.0.1:#{port}")

      client.send("hello tcp")
      msg = server.receive
      assert_equal ["hello tcp"], msg

      server.send("reply tcp")
      msg = client.receive
      assert_equal ["reply tcp"], msg
    ensure
      client&.close
      server&.close
    end
  end

  it "REQ/REP over TCP" do
    Async do
      rep = OMQ::REP.bind("tcp://127.0.0.1:0")
      port = rep.last_tcp_port

      req = OMQ::REQ.connect("tcp://127.0.0.1:#{port}")

      req.send("request")
      request = rep.receive
      assert_equal ["request"], request

      rep.send("reply")
      reply = req.receive
      assert_equal ["reply"], reply
    ensure
      req&.close
      rep&.close
    end
  end

  it "PUSH/PULL over TCP" do
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port

      push = OMQ::PUSH.connect("tcp://127.0.0.1:#{port}")

      push.send("pipeline msg")
      msg = pull.receive
      assert_equal ["pipeline msg"], msg
    ensure
      push&.close
      pull&.close
    end
  end
end
