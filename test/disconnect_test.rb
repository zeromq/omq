# frozen_string_literal: true

require_relative "test_helper"

describe "disconnect / unbind" do
  before { OMQ::ZMTP::Transport::Inproc.reset! }

  it "#disconnect closes only connections to that endpoint" do
    Async do
      pull1 = OMQ::PULL.bind("inproc://ep1")
      pull2 = OMQ::PULL.bind("inproc://ep2")

      push = OMQ::PUSH.new
      push.connect("inproc://ep1")
      push.connect("inproc://ep2")

      # Both work
      push.send("to ep1")
      assert_equal ["to ep1"], pull1.receive

      push.send("to ep2")
      assert_equal ["to ep2"], pull2.receive

      # Disconnect from ep1 only
      push.disconnect("inproc://ep1")

      # ep2 should still work
      push.send("still ep2")
      assert_equal ["still ep2"], pull2.receive
    ensure
      push&.close
      pull1&.close
      pull2&.close
    end
  end

  it "#unbind stops accepting new connections" do
    Async do
      rep = OMQ::REP.new
      rep.bind("tcp://127.0.0.1:0")
      port = rep.last_tcp_port

      req = OMQ::REQ.new
      req.connect("tcp://127.0.0.1:#{port}")

      # Works before unbind
      req.send("hello")
      msg = rep.receive
      assert_equal ["hello"], msg
      rep.send("world")
      req.receive

      # Unbind
      rep.unbind("tcp://127.0.0.1:#{port}")

      # New connections should fail
      req2 = OMQ::REQ.new
      assert_raises(Errno::ECONNREFUSED) do
        req2.connect("tcp://127.0.0.1:#{port}")
      end
    ensure
      req&.close
      req2&.close
      rep&.close
    end
  end
end
