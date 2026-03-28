# frozen_string_literal: true

require_relative "../test_helper"

begin
  require "cztop"
rescue LoadError
  # CZTop not available — skip all interop tests
end

return unless defined?(CZTop)

# Interop tests: OMQ ↔ CZTop (libzmq) over TCP.
#
# Each test verifies that OMQ's ZMTP 3.1 implementation produces
# wire-compatible frames with libzmq via CZTop.
#
describe "Interop: OMQ ↔ CZTop" do

  # Helper: allocate an ephemeral port via CZTop bind
  def cztop_bind(socket_class)
    s = socket_class.new
    s.linger = 0
    port = s.bind("tcp://127.0.0.1:*")
    [s, port]
  end

  # ── REQ/REP ──────────────────────────────────────────────────────

  describe "REQ/REP" do
    it "OMQ REQ → CZTop REP" do
      rep, port = cztop_bind(CZTop::Socket::REP)

      Async do
        req = OMQ::REQ.connect("tcp://127.0.0.1:#{port}")
        req.send("hello from omq")
        msg = rep.receive
        assert_equal ["hello from omq"], msg.to_a
        rep << "reply from cztop"
        reply = req.receive
        assert_equal ["reply from cztop"], reply
      ensure
        req&.close
      end
    ensure
      rep&.close
    end

    it "CZTop REQ → OMQ REP" do
      Async do |task|
        rep = OMQ::REP.bind("tcp://127.0.0.1:0")
        port = rep.last_tcp_port

        responder = task.async do
          msg = rep.receive
          rep << msg.map(&:upcase)
        end

        req = CZTop::Socket::REQ.new(">tcp://127.0.0.1:#{port}")
        req.linger = 0
        req << "hello from cztop"
        reply = req.receive
        assert_equal ["HELLO FROM CZTOP"], reply.to_a

        responder.wait
      ensure
        req&.close
        rep&.close
      end
    end
  end

  # ── PUSH/PULL ────────────────────────────────────────────────────

  describe "PUSH/PULL" do
    it "OMQ PUSH → CZTop PULL" do
      pull, port = cztop_bind(CZTop::Socket::PULL)

      Async do
        push = OMQ::PUSH.connect("tcp://127.0.0.1:#{port}")
        sleep 0.05
        push.send("omq message")
        msg = pull.receive
        assert_equal ["omq message"], msg.to_a
      ensure
        push&.close
      end
    ensure
      pull&.close
    end

    it "CZTop PUSH → OMQ PULL" do
      Async do
        pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
        port = pull.last_tcp_port

        push = CZTop::Socket::PUSH.new(">tcp://127.0.0.1:#{port}")
        push.linger = 0
        sleep 0.05
        push << "cztop message"
        msg = pull.receive
        assert_equal ["cztop message"], msg
      ensure
        push&.close
        pull&.close
      end
    end
  end

  # ── PUB/SUB ──────────────────────────────────────────────────────

  describe "PUB/SUB" do
    it "OMQ PUB → CZTop SUB with filtering" do
      sub = CZTop::Socket::SUB.new
      sub.linger = 0
      sub.subscribe("weather.")

      Async do
        pub = OMQ::PUB.bind("tcp://127.0.0.1:0")
        port = pub.last_tcp_port

        sub.connect("tcp://127.0.0.1:#{port}")
        sleep 0.1

        pub.send("sports.score")
        pub.send("weather.nyc 72F")

        msg = sub.receive
        assert_equal ["weather.nyc 72F"], msg.to_a
      ensure
        pub&.close
      end
    ensure
      sub&.close
    end

    it "CZTop PUB → OMQ SUB with filtering" do
      pub = CZTop::Socket::PUB.new
      pub.linger = 0
      port = pub.bind("tcp://127.0.0.1:*")

      Async do
        sub = OMQ::SUB.connect("tcp://127.0.0.1:#{port}", prefix: "alert.")
        sleep 0.1

        pub << "noise.data"
        pub << "alert.fire"

        msg = sub.receive
        assert_equal ["alert.fire"], msg
      ensure
        sub&.close
      end
    ensure
      pub&.close
    end
  end

  # ── DEALER/ROUTER ────────────────────────────────────────────────

  describe "DEALER/ROUTER" do
    it "OMQ DEALER → CZTop ROUTER" do
      router, port = cztop_bind(CZTop::Socket::ROUTER)

      Async do
        dealer = OMQ::DEALER.new
        dealer.identity = "omq-dealer"
        dealer.connect("tcp://127.0.0.1:#{port}")
        sleep 0.05

        dealer.send("hello")
        msg = router.receive
        frames = msg.to_a
        assert_equal "omq-dealer", frames[0]
        assert_equal "hello", frames[-1]
      ensure
        dealer&.close
      end
    ensure
      router&.close
    end

    it "CZTop DEALER → OMQ ROUTER" do
      Async do
        router = OMQ::ROUTER.bind("tcp://127.0.0.1:0")
        port = router.last_tcp_port

        dealer = CZTop::Socket::DEALER.new
        dealer.linger = 0
        dealer.identity = "cztop-dealer"
        dealer.connect("tcp://127.0.0.1:#{port}")
        sleep 0.05

        dealer << "from cztop"
        msg = router.receive
        assert_equal "cztop-dealer", msg[0]
        assert_equal "from cztop", msg[-1]
      ensure
        dealer&.close
        router&.close
      end
    end
  end

  # ── PAIR ─────────────────────────────────────────────────────────

  describe "PAIR" do
    it "bidirectional OMQ ↔ CZTop" do
      cztop_pair, port = cztop_bind(CZTop::Socket::PAIR)

      Async do
        omq_pair = OMQ::PAIR.connect("tcp://127.0.0.1:#{port}")
        sleep 0.05

        omq_pair.send("from omq")
        msg = cztop_pair.receive
        assert_equal ["from omq"], msg.to_a

        cztop_pair << "from cztop"
        msg = omq_pair.receive
        assert_equal ["from cztop"], msg
      ensure
        omq_pair&.close
      end
    ensure
      cztop_pair&.close
    end
  end

  # ── Edge cases ───────────────────────────────────────────────────

  describe "Edge cases" do
    it "multi-frame messages: OMQ → CZTop" do
      pull, port = cztop_bind(CZTop::Socket::PULL)

      Async do
        push = OMQ::PUSH.connect("tcp://127.0.0.1:#{port}")
        sleep 0.05
        push.send(["frame1", "frame2", "frame3"])
        msg = pull.receive
        assert_equal ["frame1", "frame2", "frame3"], msg.to_a
      ensure
        push&.close
      end
    ensure
      pull&.close
    end

    it "multi-frame messages: CZTop → OMQ" do
      Async do
        pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
        port = pull.last_tcp_port

        push = CZTop::Socket::PUSH.new(">tcp://127.0.0.1:#{port}")
        push.linger = 0
        sleep 0.05
        push << CZTop::Message.new("part1", "part2", "part3")
        msg = pull.receive
        assert_equal ["part1", "part2", "part3"], msg
      ensure
        push&.close
        pull&.close
      end
    end

    it "large messages (1MB): OMQ → CZTop" do
      pull, port = cztop_bind(CZTop::Socket::PULL)

      Async do
        push = OMQ::PUSH.connect("tcp://127.0.0.1:#{port}")
        sleep 0.05
        big = "x" * 1_000_000
        push.send(big)
        msg = pull.receive
        assert_equal 1_000_000, msg.to_a.first.bytesize
      ensure
        push&.close
      end
    ensure
      pull&.close
    end

    it "large messages (1MB): CZTop → OMQ" do
      Async do
        pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
        port = pull.last_tcp_port

        push = CZTop::Socket::PUSH.new(">tcp://127.0.0.1:#{port}")
        push.linger = 0
        sleep 0.05
        push << ("y" * 1_000_000)
        msg = pull.receive
        assert_equal 1_000_000, msg.first.bytesize
      ensure
        push&.close
        pull&.close
      end
    end

    it "binary data (all 256 byte values): OMQ → CZTop" do
      pull, port = cztop_bind(CZTop::Socket::PULL)

      Async do
        push = OMQ::PUSH.connect("tcp://127.0.0.1:#{port}")
        sleep 0.05
        binary = (0..255).map(&:chr).join.b
        push.send(binary)
        msg = pull.receive
        assert_equal binary, msg.to_a.first.b
      ensure
        push&.close
      end
    ensure
      pull&.close
    end

    it "binary data (all 256 byte values): CZTop → OMQ" do
      Async do
        pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
        port = pull.last_tcp_port

        push = CZTop::Socket::PUSH.new(">tcp://127.0.0.1:#{port}")
        push.linger = 0
        sleep 0.05
        binary = (0..255).map(&:chr).join.b
        push << binary
        msg = pull.receive
        assert_equal binary, msg.first.b
      ensure
        push&.close
        pull&.close
      end
    end

    it "empty messages: OMQ → CZTop" do
      pull, port = cztop_bind(CZTop::Socket::PULL)

      Async do
        push = OMQ::PUSH.connect("tcp://127.0.0.1:#{port}")
        sleep 0.05
        push.send("")
        msg = pull.receive
        assert_equal [""], msg.to_a
      ensure
        push&.close
      end
    ensure
      pull&.close
    end

    it "empty messages: CZTop → OMQ" do
      Async do
        pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
        port = pull.last_tcp_port

        push = CZTop::Socket::PUSH.new(">tcp://127.0.0.1:#{port}")
        push.linger = 0
        sleep 0.05
        push << ""
        msg = pull.receive
        assert_equal [""], msg
      ensure
        push&.close
        pull&.close
      end
    end
  end
end
