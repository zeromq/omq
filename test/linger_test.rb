# frozen_string_literal: true

require_relative "test_helper"

describe "Linger" do
  it "drains send queue before closing when linger > 0" do
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port

      push = OMQ::PUSH.new(nil, linger: 1)
      push.connect("tcp://127.0.0.1:#{port}")

      # Send several messages
      5.times { |i| push.send("msg-#{i}") }

      # Close with linger — should wait for messages to drain
      push.close

      # All messages should have been delivered
      5.times do |i|
        msg = pull.receive
        assert_equal ["msg-#{i}"], msg
      end
    ensure
      pull&.close
    end
  end

  it "closes immediately when linger = 0" do
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port

      push = OMQ::PUSH.new(nil, linger: 0)
      push.connect("tcp://127.0.0.1:#{port}")

      push.send("before close")

      # Close immediately — some messages may be lost
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      push.close
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

      # Close should be near-instant (< 100ms)
      assert_operator elapsed, :<, 0.1
    ensure
      pull&.close
    end
  end
end
