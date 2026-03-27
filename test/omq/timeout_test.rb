# frozen_string_literal: true

require_relative "../test_helper"

describe "send_timeout" do
  before { OMQ::ZMTP::Transport::Inproc.reset! }

  it "raises IO::TimeoutError when send blocks longer than send_timeout" do
    Async do
      # HWM=1 so second send will block waiting for a consumer
      push = OMQ::PUSH.new(nil, send_hwm: 1, send_timeout: 0.1)
      push.connect("inproc://timeout-send")

      pull = OMQ::PULL.bind("inproc://timeout-send")

      # First send fills the HWM
      push.send("fill")

      # Second send should time out
      assert_raises IO::TimeoutError do
        push.send("overflow")
      end
    ensure
      push&.close
      pull&.close
    end
  end

  it "does not raise when send completes within send_timeout" do
    Async do
      push = OMQ::PUSH.new(nil, send_timeout: 1)
      pull = OMQ::PULL.bind("inproc://timeout-send-ok")
      push.connect("inproc://timeout-send-ok")

      push.send("hello")
      msg = pull.receive
      assert_equal ["hello"], msg
    ensure
      push&.close
      pull&.close
    end
  end
end


describe "recv_timeout" do
  before { OMQ::ZMTP::Transport::Inproc.reset! }

  it "raises IO::TimeoutError when recv blocks longer than recv_timeout" do
    Async do
      pull = OMQ::PULL.new(nil, recv_timeout: 0.1)
      pull.bind("inproc://timeout-recv")

      push = OMQ::PUSH.connect("inproc://timeout-recv")

      # Don't send anything — recv should time out
      assert_raises IO::TimeoutError do
        pull.receive
      end
    ensure
      push&.close
      pull&.close
    end
  end

  it "does not raise when message arrives within recv_timeout" do
    Async do
      pull = OMQ::PULL.new(nil, recv_timeout: 2)
      pull.bind("inproc://timeout-recv-ok")

      push = OMQ::PUSH.connect("inproc://timeout-recv-ok")

      push.send("hello")
      msg = pull.receive
      assert_equal ["hello"], msg
    ensure
      push&.close
      pull&.close
    end
  end
end
