# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

describe "received messages are deep-frozen" do
  def assert_deep_frozen(msg)
    assert msg.frozen?, "message array must be frozen"
    msg.each_with_index do |part, i|
      assert part.frozen?, "part #{i} (#{part.inspect}) must be frozen"
    end
  end

  # -- send-side freezing -----------------------------------------------------

  describe "send freezes the caller's message" do
    before { OMQ::Transport::Inproc.reset! }

    it "does not freeze the original bare string (a binary copy is made)" do
      Async do
        push = OMQ::PUSH.bind("inproc://frozen-send-str")
        pull = OMQ::PULL.connect("inproc://frozen-send-str")

        msg = "mutable".dup
        push << msg
        refute msg.frozen?, "original string should not be frozen (copy is sent)"

        pull.receive # drain
      ensure
        push&.close
        pull&.close
      end
    end

    it "freezes an array and its parts" do
      Async do
        push = OMQ::PUSH.bind("inproc://frozen-send-arr")
        pull = OMQ::PULL.connect("inproc://frozen-send-arr")

        parts = ["one".dup, "two".dup]
        push << parts
        assert parts.frozen?, "array should be frozen after send"
        parts.each { |p| assert p.frozen?, "#{p.inspect} should be frozen after send" }

        pull.receive # drain
      ensure
        push&.close
        pull&.close
      end
    end

    it "handles already-frozen input" do
      Async do
        push = OMQ::PUSH.bind("inproc://frozen-send-prefrozen")
        pull = OMQ::PULL.connect("inproc://frozen-send-prefrozen")

        parts = ["already", "frozen"].freeze
        push << parts # should not raise

        msg = pull.receive
        assert_equal ["already", "frozen"], msg
      ensure
        push&.close
        pull&.close
      end
    end
  end

  # -- inproc ----------------------------------------------------------------

  describe "inproc" do
    before { OMQ::Transport::Inproc.reset! }

    it "PUSH/PULL" do
      Async do
        push = OMQ::PUSH.bind("inproc://frozen-pushpull")
        pull = OMQ::PULL.connect("inproc://frozen-pushpull")

        push << "hello"
        assert_deep_frozen pull.receive
      ensure
        push&.close
        pull&.close
      end
    end

    it "REQ/REP" do
      Async do
        rep = OMQ::REP.bind("inproc://frozen-reqrep")
        req = OMQ::REQ.connect("inproc://frozen-reqrep")

        req << "request"
        msg = rep.receive
        assert_deep_frozen msg

        rep << "reply"
        assert_deep_frozen req.receive
      ensure
        req&.close
        rep&.close
      end
    end

    it "ROUTER/DEALER" do
      Async do
        router = OMQ::ROUTER.bind("inproc://frozen-rd")
        dealer = OMQ::DEALER.new
        dealer.identity = "d1"
        dealer.connect("inproc://frozen-rd")

        dealer << "hello"
        assert_deep_frozen router.receive
      ensure
        dealer&.close
        router&.close
      end
    end

    it "multi-frame messages" do
      Async do
        push = OMQ::PUSH.bind("inproc://frozen-multi")
        pull = OMQ::PULL.connect("inproc://frozen-multi")

        push << ["part1", "part2", "part3"]
        msg = pull.receive
        assert_deep_frozen msg
        assert_equal 3, msg.size
      ensure
        push&.close
        pull&.close
      end
    end
  end

  # -- TCP -------------------------------------------------------------------

  describe "TCP" do
    it "PUSH/PULL" do
      Async do
        pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
        push = OMQ::PUSH.connect("tcp://127.0.0.1:#{pull.last_tcp_port}")

        push << "hello"
        assert_deep_frozen pull.receive
      ensure
        push&.close
        pull&.close
      end
    end

    it "REQ/REP" do
      Async do
        rep = OMQ::REP.bind("tcp://127.0.0.1:0")
        req = OMQ::REQ.connect("tcp://127.0.0.1:#{rep.last_tcp_port}")

        req << "request"
        msg = rep.receive
        assert_deep_frozen msg

        rep << "reply"
        assert_deep_frozen req.receive
      ensure
        req&.close
        rep&.close
      end
    end

    it "multi-frame messages" do
      Async do
        pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
        push = OMQ::PUSH.connect("tcp://127.0.0.1:#{pull.last_tcp_port}")

        push << ["part1", "part2", "part3"]
        msg = pull.receive
        assert_deep_frozen msg
        assert_equal 3, msg.size
      ensure
        push&.close
        pull&.close
      end
    end
  end

  # -- IPC -------------------------------------------------------------------

  describe "IPC" do
    it "PUSH/PULL" do
      Async do
        pull = OMQ::PULL.bind("ipc://@omq-frozen-pp-#{$$}")
        push = OMQ::PUSH.connect("ipc://@omq-frozen-pp-#{$$}")

        push << "hello"
        assert_deep_frozen pull.receive
      ensure
        push&.close
        pull&.close
      end
    end

    it "REQ/REP" do
      Async do
        rep = OMQ::REP.bind("ipc://@omq-frozen-rr-#{$$}")
        req = OMQ::REQ.connect("ipc://@omq-frozen-rr-#{$$}")

        req << "request"
        msg = rep.receive
        assert_deep_frozen msg

        rep << "reply"
        assert_deep_frozen req.receive
      ensure
        req&.close
        rep&.close
      end
    end
  end
end
