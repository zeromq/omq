# frozen_string_literal: true

require_relative "test_helper"

describe "Socket types over inproc" do
  before do
    OMQ::ZMTP::Transport::Inproc.reset!
  end

  describe "PUSH/PULL" do
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
  end

  describe "REQ/REP" do
    it "completes a request-reply cycle" do
      Async do
        rep = OMQ::REP.bind("inproc://reqrep-1")
        req = OMQ::REQ.connect("inproc://reqrep-1")

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

    it "handles multi-frame request/reply" do
      Async do
        rep = OMQ::REP.bind("inproc://reqrep-2")
        req = OMQ::REQ.connect("inproc://reqrep-2")

        req.send(["part1", "part2"])
        request = rep.receive
        assert_equal ["part1", "part2"], request

        rep.send(["reply1", "reply2"])
        reply = req.receive
        assert_equal ["reply1", "reply2"], reply
      ensure
        req&.close
        rep&.close
      end
    end
  end

  describe "DEALER/ROUTER" do
    it "routes messages by identity" do
      Async do
        router = OMQ::ROUTER.bind("inproc://dealerrouter-1")
        dealer = OMQ::DEALER.new
        dealer.options.identity = "dealer-1"
        dealer.connect("inproc://dealerrouter-1")

        dealer.send("hello from dealer")
        msg = router.receive
        # ROUTER prepends identity frame
        assert_equal "dealer-1", msg[0]
        assert_equal "hello from dealer", msg[1]

        # Route reply back using identity
        router.send_to(msg[0], "hello back")
        reply = dealer.receive
        # DEALER sees the empty delimiter + message
        assert_equal ["", "hello back"], reply
      ensure
        dealer&.close
        router&.close
      end
    end
  end

  describe "PUB/SUB" do
    it "delivers messages matching subscription" do
      Async do
        pub = OMQ::PUB.bind("inproc://pubsub-1")
        sub = OMQ::SUB.connect("inproc://pubsub-1")
        sub.subscribe("topic.")

        # Give subscription time to propagate
        Async::Task.current.yield

        pub.send("topic.hello")
        msg = sub.receive
        assert_equal ["topic.hello"], msg
      ensure
        sub&.close
        pub&.close
      end
    end
  end

  describe "PAIR" do
    it "bidirectional communication" do
      Async do
        a = OMQ::PAIR.bind("inproc://pair-bidir")
        b = OMQ::PAIR.connect("inproc://pair-bidir")

        b.send("from b")
        assert_equal ["from b"], a.receive

        a.send("from a")
        assert_equal ["from a"], b.receive
      ensure
        a&.close
        b&.close
      end
    end
  end
end
