# frozen_string_literal: true

require_relative "test_helper"
require "cztop"

describe "CURVE interop with CZTop/libzmq" do
  def generate_keypair
    CZTop::CURVE.keypair # => [public_key(32 bytes), secret_key(32 bytes)]
  end

  describe "REQ/REP" do
    it "OMQ client → CZTop server" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      rep = CZTop::Socket::REP.new
      CZTop::CURVE.setup_server!(rep, server_sec)
      rep.linger       = 0
      rep.recv_timeout = 5
      port = rep.bind("tcp://127.0.0.1:*")

      server_thread = Thread.new do
        msg = rep.receive
        rep << msg.first.upcase
      end

      Async do
        req = OMQ::REQ.new
        req.mechanism        = :curve
        req.curve_server     = false
        req.curve_public_key = client_pub
        req.curve_secret_key = client_sec
        req.curve_server_key = server_pub
        req.connect("tcp://127.0.0.1:#{port}")

        req << "hello from omq"
        reply = req.receive
        assert_equal ["HELLO FROM OMQ"], reply
      ensure
        req&.close
      end

      server_thread.join(8)
      rep.close
    end

    it "CZTop client → OMQ server" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      reply = nil

      Async do |task|
        rep = OMQ::REP.new
        rep.mechanism        = :curve
        rep.curve_server     = true
        rep.curve_public_key = server_pub
        rep.curve_secret_key = server_sec
        rep.bind("tcp://127.0.0.1:0")
        port = rep.last_tcp_port

        task.async do
          msg = rep.receive
          rep << msg.map(&:upcase)
        end

        client_thread = Thread.new do
          req = CZTop::Socket::REQ.new
          CZTop::CURVE.setup_client!(req, client_sec, server_pub)
          req.linger       = 0
          req.send_timeout = 5
          req.recv_timeout = 5
          req.connect("tcp://127.0.0.1:#{port}")

          req << "hello from cztop"
          reply = req.receive
          req.close
        end

        client_thread.join(8)
      ensure
        rep&.close
      end

      assert_equal ["HELLO FROM CZTOP"], reply
    end
  end

  describe "DEALER/ROUTER" do
    it "OMQ DEALER → CZTop ROUTER" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      router = CZTop::Socket::ROUTER.new
      CZTop::CURVE.setup_server!(router, server_sec)
      router.linger       = 0
      router.recv_timeout = 5
      port = router.bind("tcp://127.0.0.1:*")

      server_thread = Thread.new do
        msg = router.receive
        # CZTop ROUTER receives [identity, "", payload]
        identity = msg[0]
        payload  = msg[-1]
        router.send_to(identity, payload.upcase)
      end

      Async do
        dealer = OMQ::DEALER.new
        dealer.mechanism        = :curve
        dealer.curve_server     = false
        dealer.curve_public_key = client_pub
        dealer.curve_secret_key = client_sec
        dealer.curve_server_key = server_pub
        dealer.connect("tcp://127.0.0.1:#{port}")

        dealer << ["", "hello from dealer"]
        reply = dealer.receive
        assert_equal "HELLO FROM DEALER", reply.last
      ensure
        dealer&.close
      end

      server_thread.join(8)
      router.close
    end

    it "CZTop DEALER → OMQ ROUTER" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      reply = nil

      Async do |task|
        router = OMQ::ROUTER.new
        router.mechanism        = :curve
        router.curve_server     = true
        router.curve_public_key = server_pub
        router.curve_secret_key = server_sec
        router.bind("tcp://127.0.0.1:0")
        port = router.last_tcp_port

        task.async do
          msg = router.receive
          # msg = [identity, "", payload]
          identity = msg.first
          router << [identity, "", msg.last.upcase]
        end

        client_thread = Thread.new do
          dealer = CZTop::Socket::DEALER.new
          CZTop::CURVE.setup_client!(dealer, client_sec, server_pub)
          dealer.linger       = 0
          dealer.send_timeout = 5
          dealer.recv_timeout = 5
          dealer.connect("tcp://127.0.0.1:#{port}")

          dealer << ["", "hello from cztop dealer"]
          reply = dealer.receive
          dealer.close
        end

        client_thread.join(8)
      ensure
        router&.close
      end

      assert_equal "HELLO FROM CZTOP DEALER", reply&.last
    end
  end

  describe "Authentication interop" do
    it "OMQ server rejects unauthorized CZTop client" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair
      allowed_pub, _         = generate_keypair

      rejected = false

      Async do |task|
        rep = OMQ::REP.new
        rep.mechanism           = :curve
        rep.curve_server        = true
        rep.curve_public_key    = server_pub
        rep.curve_secret_key    = server_sec
        rep.curve_authenticator = Set[allowed_pub]  # client_pub NOT in set
        rep.bind("tcp://127.0.0.1:0")
        port = rep.last_tcp_port

        client_thread = Thread.new do
          req = CZTop::Socket::REQ.new
          CZTop::CURVE.setup_client!(req, client_sec, server_pub)
          req.linger       = 0
          req.send_timeout = 2
          req.recv_timeout = 2
          req.connect("tcp://127.0.0.1:#{port}")

          begin
            req << "should be rejected"
            req.receive
          rescue IO::TimeoutError
            rejected = true
          end
          req.close
        end

        client_thread.join(5)
      ensure
        rep&.close
      end

      assert rejected, "expected CZTop client to be rejected by authenticator"
    end
  end
end
