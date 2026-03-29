# frozen_string_literal: true

require_relative "../test_helper"
require "pathname"

describe "PUSH/PULL over inproc" do
  before { OMQ::ZMTP::Transport::Inproc.reset! }

  it "sends and receives messages" do
    Async do
      pull = OMQ::PULL.bind("inproc://pushpull-1")
      push = OMQ::PUSH.connect("inproc://pushpull-1")

      push.send("hello")
      msg = pull.receive
      assert_equal ["hello"], msg
    ensure
      push&.close
      pull&.close
    end
  end

  it "round-robins across multiple PULL peers" do
    Async do
      pull1 = OMQ::PULL.bind("inproc://pushpull-rr-1")
      pull2 = OMQ::PULL.bind("inproc://pushpull-rr-2")

      push = OMQ::PUSH.new
      push.connect("inproc://pushpull-rr-1")
      push.connect("inproc://pushpull-rr-2")

      push.send("msg1")
      push.send("msg2")

      msg1 = pull1.receive
      msg2 = pull2.receive

      assert_equal ["msg1"], msg1
      assert_equal ["msg2"], msg2
    ensure
      push&.close
      pull1&.close
      pull2&.close
    end
  end
  it "rejects non-string parts with TypeError" do
    Async do
      push = OMQ::PUSH.bind("inproc://pushpull-type")
      assert_raises(NoMethodError) { push.send([123]) }
      assert_raises(NoMethodError) { push.send([:symbol]) }
      assert_raises(NoMethodError) { push.send([nil]) }
    ensure
      push&.close
    end
  end

  it "accepts objects that respond to #to_str" do
    Async do
      pull = OMQ::PULL.bind("inproc://pushpull-tostr")
      push = OMQ::PUSH.connect("inproc://pushpull-tostr")

      push.send([Pathname.new("/tmp")])
      msg = pull.receive
      assert_equal ["/tmp"], msg
    ensure
      push&.close
      pull&.close
    end
  end
end


describe "PUSH/PULL delivery guarantees" do
  before { OMQ::ZMTP::Transport::Inproc.reset! }

  # -- connect before bind (inproc) ----------------------------------------

  it "delivers messages when inproc connect happens before bind" do
    Async do
      push = OMQ::PUSH.new(nil, linger: 1)
      push.connect("inproc://dg-inproc-cb")

      # Send while no peer is bound yet
      push.send("early-1")
      push.send("early-2")

      # Now bind
      pull = OMQ::PULL.bind("inproc://dg-inproc-cb")

      # Give reconnect a moment
      sleep 0.05

      push.send("late-1")

      msgs = []
      3.times do
        Async::Task.current.with_timeout(2) do
          msgs << pull.receive
        end
      end
      assert_equal [["early-1"], ["early-2"], ["late-1"]], msgs
    ensure
      push&.close
      pull&.close
    end
  end

  # -- bind before connect (inproc) ----------------------------------------

  it "delivers messages when inproc bind happens before connect" do
    Async do
      pull = OMQ::PULL.bind("inproc://dg-inproc-bc")
      push = OMQ::PUSH.connect("inproc://dg-inproc-bc")

      10.times { |i| push.send("msg-#{i}") }

      10.times do |i|
        msg = Async::Task.current.with_timeout(2) do
          pull.receive
        end
        assert_equal ["msg-#{i}"], msg
      end
    ensure
      push&.close
      pull&.close
    end
  end

  # -- connect before bind (IPC) -------------------------------------------

  it "delivers messages when IPC connect happens before bind" do
    Async do
      path = "/tmp/omq-test-dg-ipc-cb-#{$$}.sock"
      push = OMQ::PUSH.new(nil, linger: 1)
      push.reconnect_interval = 0.05
      push.connect("ipc://#{path}")

      push.send("early-1")

      sleep 0.02
      pull = OMQ::PULL.bind("ipc://#{path}")
      sleep 0.1

      push.send("late-1")

      msgs = []
      2.times do
        Async::Task.current.with_timeout(2) do
          msgs << pull.receive
        end
      end
      assert_equal [["early-1"], ["late-1"]], msgs
    ensure
      push&.close
      pull&.close
      File.delete(path) rescue nil
    end
  end

  # -- bind before connect (IPC) -------------------------------------------

  it "delivers messages when IPC bind happens before connect" do
    Async do
      path = "/tmp/omq-test-dg-ipc-bc-#{$$}.sock"
      pull = OMQ::PULL.bind("ipc://#{path}")

      push = OMQ::PUSH.new(nil, linger: 1)
      push.connect("ipc://#{path}")
      sleep 0.05

      5.times { |i| push.send("msg-#{i}") }

      5.times do |i|
        msg = Async::Task.current.with_timeout(2) do
          pull.receive
        end
        assert_equal ["msg-#{i}"], msg
      end
    ensure
      push&.close
      pull&.close
      File.delete(path) rescue nil
    end
  end

  # -- connect before bind (TCP) -------------------------------------------

  it "delivers messages when TCP connect happens before bind" do
    Async do
      push = OMQ::PUSH.new(nil, linger: 1)
      push.reconnect_interval = 0.05
      push.connect("tcp://127.0.0.1:19890")

      push.send("early-1")

      sleep 0.02
      pull = OMQ::PULL.bind("tcp://127.0.0.1:19890")
      sleep 0.1

      push.send("late-1")

      msgs = []
      2.times do
        Async::Task.current.with_timeout(2) do
          msgs << pull.receive
        end
      end
      assert_equal [["early-1"], ["late-1"]], msgs
    ensure
      push&.close
      pull&.close
    end
  end

  # -- bind before connect (TCP) -------------------------------------------

  it "delivers messages when TCP bind happens before connect" do
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port

      push = OMQ::PUSH.new(nil, linger: 1)
      push.connect("tcp://127.0.0.1:#{port}")
      sleep 0.05

      5.times { |i| push.send("msg-#{i}") }

      5.times do |i|
        msg = Async::Task.current.with_timeout(2) do
          pull.receive
        end
        assert_equal ["msg-#{i}"], msg
      end
    ensure
      push&.close
      pull&.close
    end
  end

  # -- ordered delivery, no drops -------------------------------------------

  it "delivers all messages in order with no drops" do
    Async do
      pull = OMQ::PULL.bind("inproc://dg-order")
      push = OMQ::PUSH.connect("inproc://dg-order")

      n = 100
      n.times { |i| push.send("seq-#{i}") }

      received = []
      n.times do
        msg = Async::Task.current.with_timeout(2) do
          pull.receive
        end
        received << msg.first
      end

      expected = n.times.map { |i| "seq-#{i}" }
      assert_equal expected, received
    ensure
      push&.close
      pull&.close
    end
  end

  # -- busy fiber during reconnect -----------------------------------------

  it "does not drop messages when receiver fiber is busy during TCP reconnect" do
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port

      push = OMQ::PUSH.new(nil, linger: 1)
      push.reconnect_interval = 0.05
      push.connect("tcp://127.0.0.1:#{port}")
      sleep 0.05

      # Send first batch
      5.times { |i| push.send("batch1-#{i}") }

      # Simulate busy receiver — sleep before draining
      sleep 0.05

      # Receive first batch
      5.times do |i|
        msg = Async::Task.current.with_timeout(2) do
          pull.receive
        end
        assert_equal ["batch1-#{i}"], msg
      end

      # Send second batch
      5.times { |i| push.send("batch2-#{i}") }

      5.times do |i|
        msg = Async::Task.current.with_timeout(2) do
          pull.receive
        end
        assert_equal ["batch2-#{i}"], msg
      end
    ensure
      push&.close
      pull&.close
    end
  end
end
