# frozen_string_literal: true

require_relative "../test_helper"

describe "Non-blocking TCP connect" do
  it "connect returns immediately even when endpoint is unreachable" do
    Async do
      req = OMQ::REQ.new(nil, linger: 0)
      req.reconnect_interval = 0.05

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Connect to 3 endpoints — none are listening.
      # With blocking connect, each would wait for OS timeout (~2 min).
      req.connect("tcp://127.0.0.1:19871")
      req.connect("tcp://127.0.0.1:19872")
      req.connect("tcp://127.0.0.1:19873")

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      # All three should return instantly (well under 1 second).
      assert_operator elapsed, :<, 0.5,
        "connect should not block (took #{elapsed}s)"
    ensure
      req&.close
    end
  end

  it "connects in background and succeeds when server appears" do
    Async do
      req = OMQ::REQ.new(nil, linger: 0)
      req.reconnect_interval = 0.05
      req.connect("tcp://127.0.0.1:19874")

      # Server starts after client — connect already returned
      sleep 0.05
      rep = OMQ::REP.new(nil, linger: 0)
      rep.bind("tcp://127.0.0.1:19874")

      # Wait for background connect to succeed
      sleep 0.15

      req.send("async connect")
      msg = rep.receive
      assert_equal ["async connect"], msg
    ensure
      req&.close
      rep&.close
    end
  end
end
