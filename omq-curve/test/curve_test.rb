# frozen_string_literal: true

require_relative "test_helper"
require "socket"

describe "CURVE encryption" do
  # Generate keypairs for server and client
  def generate_keypair
    secret = RbNaCl::PrivateKey.generate
    [secret.public_key.to_s, secret.to_s]
  end

  def make_socketpair
    UNIXSocket.pair.map { |s| OMQ::ZMTP::Transport::TCP::SocketIO.new(s) }
  end

  describe "Connection-level handshake" do
    it "completes CURVE handshake between client and server" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      Async do
        client_io, server_io = make_socketpair

        server_mechanism = OMQ::ZMTP::Mechanism::Curve.new(
          server_key: server_pub,
          public_key: server_pub,
          secret_key: server_sec,
          as_server:  true,
        )

        client_mechanism = OMQ::ZMTP::Mechanism::Curve.new(
          server_key: server_pub,
          public_key: client_pub,
          secret_key: client_sec,
          as_server:  false,
        )

        server = OMQ::ZMTP::Connection.new(
          server_io,
          socket_type: "REP",
          as_server:   true,
          mechanism:   server_mechanism,
        )

        client = OMQ::ZMTP::Connection.new(
          client_io,
          socket_type: "REQ",
          as_server:   false,
          mechanism:   client_mechanism,
        )

        server_task = Async { server.handshake! }
        client_task = Async { client.handshake! }

        client_task.wait
        server_task.wait

        assert_equal "REP", client.peer_socket_type
        assert_equal "REQ", server.peer_socket_type
      ensure
        client_io&.close
        server_io&.close
      end
    end

    it "sends and receives encrypted messages" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      Async do
        client_io, server_io = make_socketpair

        server_mechanism = OMQ::ZMTP::Mechanism::Curve.new(
          server_key: server_pub,
          public_key: server_pub,
          secret_key: server_sec,
          as_server:  true,
        )

        client_mechanism = OMQ::ZMTP::Mechanism::Curve.new(
          server_key: server_pub,
          public_key: client_pub,
          secret_key: client_sec,
          as_server:  false,
        )

        server = OMQ::ZMTP::Connection.new(
          server_io,
          socket_type: "PAIR",
          as_server:   true,
          mechanism:   server_mechanism,
        )

        client = OMQ::ZMTP::Connection.new(
          client_io,
          socket_type: "PAIR",
          as_server:   false,
          mechanism:   client_mechanism,
        )

        [Async { server.handshake! }, Async { client.handshake! }].each(&:wait)

        # Send from client to server
        Async { client.send_message(["hello", "world"]) }
        msg = nil
        Async { msg = server.receive_message }.wait

        assert_equal ["hello", "world"], msg

        # Send from server to client
        Async { server.send_message(["reply"]) }
        msg2 = nil
        Async { msg2 = client.receive_message }.wait

        assert_equal ["reply"], msg2
      ensure
        client_io&.close
        server_io&.close
      end
    end

    it "rejects wrong server key" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      Async do |task|
        client_io, server_io = make_socketpair

        server_mechanism = OMQ::ZMTP::Mechanism::Curve.new(
          server_key: server_pub,
          public_key: server_pub,
          secret_key: server_sec,
          as_server:  true,
        )

        # Client uses wrong server key
        wrong_pub, _ = generate_keypair
        client_mechanism = OMQ::ZMTP::Mechanism::Curve.new(
          server_key: wrong_pub,
          public_key: client_pub,
          secret_key: client_sec,
          as_server:  false,
        )

        server = OMQ::ZMTP::Connection.new(
          server_io,
          socket_type: "REP",
          as_server:   true,
          mechanism:   server_mechanism,
        )

        client = OMQ::ZMTP::Connection.new(
          client_io,
          socket_type: "REQ",
          as_server:   false,
          mechanism:   client_mechanism,
        )

        errors = []
        server_task = Async do
          server.handshake!
        rescue OMQ::ZMTP::ProtocolError, EOFError, RbNaCl::CryptoError => e
          errors << e
          server_io.close rescue nil
        end

        client_task = Async do
          client.handshake!
        rescue OMQ::ZMTP::ProtocolError, EOFError, RbNaCl::CryptoError => e
          errors << e
          client_io.close rescue nil
        end

        task.with_timeout(5) do
          server_task.wait
          client_task.wait
        end

        refute_empty errors, "expected handshake to fail with wrong server key"
      ensure
        client_io&.close rescue nil
        server_io&.close rescue nil
      end
    end
  end

  describe "Socket-level with options" do
    it "works end-to-end over tcp with REQ/REP" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      Async do |task|
        rep = OMQ::REP.new
        rep.mechanism       = :curve
        rep.curve_server    = true
        rep.curve_public_key = server_pub
        rep.curve_secret_key = server_sec
        rep.curve_server_key = server_pub
        rep.bind("tcp://127.0.0.1:0")

        port = rep.last_tcp_port

        req = OMQ::REQ.new
        req.mechanism       = :curve
        req.curve_server    = false
        req.curve_public_key = client_pub
        req.curve_secret_key = client_sec
        req.curve_server_key = server_pub
        req.connect("tcp://127.0.0.1:#{port}")

        task.async do
          msg = rep.receive
          rep << msg.map(&:upcase)
        end

        req << "hello"
        reply = req.receive
        assert_equal ["HELLO"], reply
      ensure
        req&.close
        rep&.close
      end
    end

    it "works end-to-end over ipc with PUB/SUB" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair
      addr = "ipc:///tmp/omq_curve_test_#{$$}.sock"

      Async do |task|
        pub = OMQ::PUB.new
        pub.mechanism       = :curve
        pub.curve_server    = true
        pub.curve_public_key = server_pub
        pub.curve_secret_key = server_sec
        pub.curve_server_key = server_pub
        pub.bind(addr)

        sub = OMQ::SUB.new
        sub.mechanism       = :curve
        sub.curve_server    = false
        sub.curve_public_key = client_pub
        sub.curve_secret_key = client_sec
        sub.curve_server_key = server_pub
        sub.connect(addr)
        sub.subscribe("")

        # Allow subscription to propagate
        sleep 0.1

        task.async { pub << "encrypted news" }
        msg = sub.receive
        assert_equal ["encrypted news"], msg
      ensure
        pub&.close
        sub&.close
      end
    end
  end

  describe "Authentication" do
    it "allows a client in the allowed Set" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      Async do |task|
        rep = OMQ::REP.new
        rep.mechanism           = :curve
        rep.curve_server        = true
        rep.curve_public_key    = server_pub
        rep.curve_secret_key    = server_sec
        rep.curve_authenticator = Set[client_pub]
        rep.bind("tcp://127.0.0.1:0")
        port = rep.last_tcp_port

        task.async do
          msg = rep.receive
          rep << msg.map(&:upcase)
        end

        req = OMQ::REQ.new
        req.mechanism        = :curve
        req.curve_server     = false
        req.curve_public_key = client_pub
        req.curve_secret_key = client_sec
        req.curve_server_key = server_pub
        req.connect("tcp://127.0.0.1:#{port}")

        req << "authenticated"
        reply = req.receive
        assert_equal ["AUTHENTICATED"], reply
      ensure
        req&.close
        rep&.close
      end
    end

    it "rejects a client not in the allowed Set" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair
      other_pub, _           = generate_keypair

      Async do |task|
        rep = OMQ::REP.new
        rep.mechanism           = :curve
        rep.curve_server        = true
        rep.curve_public_key    = server_pub
        rep.curve_secret_key    = server_sec
        rep.curve_authenticator = Set[other_pub]  # only other_pub is allowed
        rep.bind("tcp://127.0.0.1:0")
        port = rep.last_tcp_port

        req = OMQ::REQ.new
        req.mechanism        = :curve
        req.curve_server     = false
        req.curve_public_key = client_pub
        req.curve_secret_key = client_sec
        req.curve_server_key = server_pub
        req.recv_timeout     = 1
        req.send_timeout     = 1
        req.connect("tcp://127.0.0.1:#{port}")

        req << "should fail"
        assert_raises(IO::TimeoutError) { req.receive }
      ensure
        req&.close
        rep&.close
      end
    end

    it "works with a callable authenticator" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      authenticated_keys = []

      Async do |task|
        rep = OMQ::REP.new
        rep.mechanism           = :curve
        rep.curve_server        = true
        rep.curve_public_key    = server_pub
        rep.curve_secret_key    = server_sec
        rep.curve_authenticator = ->(key) {
          authenticated_keys << key
          true
        }
        rep.bind("tcp://127.0.0.1:0")
        port = rep.last_tcp_port

        task.async do
          msg = rep.receive
          rep << msg.map(&:upcase)
        end

        req = OMQ::REQ.new
        req.mechanism        = :curve
        req.curve_server     = false
        req.curve_public_key = client_pub
        req.curve_secret_key = client_sec
        req.curve_server_key = server_pub
        req.connect("tcp://127.0.0.1:#{port}")

        req << "hello"
        reply = req.receive
        assert_equal ["HELLO"], reply
        assert_equal [client_pub], authenticated_keys
      ensure
        req&.close
        rep&.close
      end
    end

    it "rejects when callable returns false" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      Async do |task|
        rep = OMQ::REP.new
        rep.mechanism           = :curve
        rep.curve_server        = true
        rep.curve_public_key    = server_pub
        rep.curve_secret_key    = server_sec
        rep.curve_authenticator = ->(_key) { false }
        rep.bind("tcp://127.0.0.1:0")
        port = rep.last_tcp_port

        req = OMQ::REQ.new
        req.mechanism        = :curve
        req.curve_server     = false
        req.curve_public_key = client_pub
        req.curve_secret_key = client_sec
        req.curve_server_key = server_pub
        req.recv_timeout     = 1
        req.send_timeout     = 1
        req.connect("tcp://127.0.0.1:#{port}")

        req << "should fail"
        assert_raises(IO::TimeoutError) { req.receive }
      ensure
        req&.close
        rep&.close
      end
    end
  end

  describe "Edge cases" do
    it "ciphertext has high Shannon entropy" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      Async do
        client_io, server_io = make_socketpair

        server_mech = OMQ::ZMTP::Mechanism::Curve.new(
          public_key: server_pub, secret_key: server_sec, as_server: true,
        )
        client_mech = OMQ::ZMTP::Mechanism::Curve.new(
          server_key: server_pub, public_key: client_pub, secret_key: client_sec,
        )

        server = OMQ::ZMTP::Connection.new(server_io, socket_type: "PAIR", as_server: true, mechanism: server_mech)
        client = OMQ::ZMTP::Connection.new(client_io, socket_type: "PAIR", as_server: false, mechanism: client_mech)

        [Async { server.handshake! }, Async { client.handshake! }].each(&:wait)

        # Send a highly repetitive message
        plaintext = "A" * 1024

        # Capture raw wire bytes
        captured = "".b
        original_write = client_io.method(:write)
        client_io.define_singleton_method(:write) do |data|
          captured << data
          original_write.call(data)
        end

        Async { client.send_message([plaintext]) }
        Async { server.receive_message }.wait

        # Shannon entropy of captured ciphertext (skip ZMTP frame header)
        bytes = captured.bytes
        freq  = bytes.tally
        total = bytes.size.to_f
        entropy = -freq.values.sum { |c| p = c / total; p * Math.log2(p) }

        # Random data has ~8 bits/byte entropy. Encrypted data should be > 7.
        # The plaintext "AAAA..." has ~0 bits/byte entropy.
        assert entropy > 7.0, "expected high entropy (got #{entropy.round(2)} bits/byte)"
      ensure
        client_io&.close
        server_io&.close
      end
    end

    it "rejects replayed nonce" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      Async do
        client_io, server_io = make_socketpair

        server_mech = OMQ::ZMTP::Mechanism::Curve.new(
          public_key: server_pub, secret_key: server_sec, as_server: true,
        )
        client_mech = OMQ::ZMTP::Mechanism::Curve.new(
          server_key: server_pub, public_key: client_pub, secret_key: client_sec,
        )

        server = OMQ::ZMTP::Connection.new(server_io, socket_type: "PAIR", as_server: true, mechanism: server_mech)
        client = OMQ::ZMTP::Connection.new(client_io, socket_type: "PAIR", as_server: false, mechanism: client_mech)

        [Async { server.handshake! }, Async { client.handshake! }].each(&:wait)

        # Send a legitimate message and capture the wire bytes
        captured = "".b
        original_write = client_io.method(:write)
        client_io.define_singleton_method(:write) do |data|
          captured << data
          original_write.call(data)
        end

        Async { client.send_message(["legit"]) }
        Async { server.receive_message }.wait

        # Replay the same wire bytes (same nonce)
        original_write.call(captured)

        # Server should reject the replayed frame
        assert_raises(OMQ::ZMTP::ProtocolError) do
          Async { server.receive_message }.wait
        end
      ensure
        client_io&.close
        server_io&.close
      end
    end

    it "handles multipart messages under CURVE" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      Async do
        client_io, server_io = make_socketpair

        server_mech = OMQ::ZMTP::Mechanism::Curve.new(
          public_key: server_pub, secret_key: server_sec, as_server: true,
        )
        client_mech = OMQ::ZMTP::Mechanism::Curve.new(
          server_key: server_pub, public_key: client_pub, secret_key: client_sec,
        )

        server = OMQ::ZMTP::Connection.new(server_io, socket_type: "PAIR", as_server: true, mechanism: server_mech)
        client = OMQ::ZMTP::Connection.new(client_io, socket_type: "PAIR", as_server: false, mechanism: client_mech)

        [Async { server.handshake! }, Async { client.handshake! }].each(&:wait)

        parts = ["routing-key", "header", "payload-body"]
        Async { client.send_message(parts) }
        msg = nil
        Async { msg = server.receive_message }.wait

        assert_equal parts, msg
      ensure
        client_io&.close
        server_io&.close
      end
    end

    it "handles large messages (64 KB)" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

      Async do
        client_io, server_io = make_socketpair

        server_mech = OMQ::ZMTP::Mechanism::Curve.new(
          public_key: server_pub, secret_key: server_sec, as_server: true,
        )
        client_mech = OMQ::ZMTP::Mechanism::Curve.new(
          server_key: server_pub, public_key: client_pub, secret_key: client_sec,
        )

        server = OMQ::ZMTP::Connection.new(server_io, socket_type: "PAIR", as_server: true, mechanism: server_mech)
        client = OMQ::ZMTP::Connection.new(client_io, socket_type: "PAIR", as_server: false, mechanism: client_mech)

        [Async { server.handshake! }, Async { client.handshake! }].each(&:wait)

        large = RbNaCl::Random.random_bytes(65_536)
        Async { client.send_message([large]) }
        msg = nil
        Async { msg = server.receive_message }.wait

        assert_equal [large], msg
      ensure
        client_io&.close
        server_io&.close
      end
    end

    it "supports multiple clients to one server" do
      server_pub, server_sec = generate_keypair
      client1_pub, client1_sec = generate_keypair
      client2_pub, client2_sec = generate_keypair

      Async do |task|
        rep = OMQ::REP.new
        rep.mechanism        = :curve
        rep.curve_server     = true
        rep.curve_public_key = server_pub
        rep.curve_secret_key = server_sec
        rep.bind("tcp://127.0.0.1:0")
        port = rep.last_tcp_port

        task.async do
          2.times do
            msg = rep.receive
            rep << msg.map(&:upcase)
          end
        end

        req1 = OMQ::REQ.new
        req1.mechanism        = :curve
        req1.curve_public_key = client1_pub
        req1.curve_secret_key = client1_sec
        req1.curve_server_key = server_pub
        req1.connect("tcp://127.0.0.1:#{port}")

        req2 = OMQ::REQ.new
        req2.mechanism        = :curve
        req2.curve_public_key = client2_pub
        req2.curve_secret_key = client2_sec
        req2.curve_server_key = server_pub
        req2.connect("tcp://127.0.0.1:#{port}")

        req1 << "from client 1"
        assert_equal ["FROM CLIENT 1"], req1.receive

        req2 << "from client 2"
        assert_equal ["FROM CLIENT 2"], req2.receive
      ensure
        req1&.close
        req2&.close
        rep&.close
      end
    end

    it "reconnects after server restart" do
      server_pub, server_sec = generate_keypair
      client_pub, client_sec = generate_keypair

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

        req = OMQ::REQ.new
        req.mechanism           = :curve
        req.curve_public_key    = client_pub
        req.curve_secret_key    = client_sec
        req.curve_server_key    = server_pub
        req.reconnect_interval  = 0.1
        req.connect("tcp://127.0.0.1:#{port}")

        req << "first"
        assert_equal ["FIRST"], req.receive

        # Kill server
        rep.close

        # Restart server on same port
        rep2 = OMQ::REP.new
        rep2.mechanism        = :curve
        rep2.curve_server     = true
        rep2.curve_public_key = server_pub
        rep2.curve_secret_key = server_sec
        rep2.bind("tcp://127.0.0.1:#{port}")

        task.async do
          msg = rep2.receive
          rep2 << msg.map(&:upcase)
        end

        # Client should reconnect and complete a new handshake
        sleep 0.3
        req << "second"
        reply = req.receive
        assert_equal ["SECOND"], reply
      ensure
        req&.close
        rep&.close rescue nil
        rep2&.close rescue nil
      end
    end

    it "raises on invalid key length" do
      assert_raises(ArgumentError) do
        OMQ::ZMTP::Mechanism::Curve.new(
          server_key: "too short",
          public_key: "too short",
          secret_key: "too short",
        )
      end
    end

    it "raises on nil keys" do
      assert_raises(ArgumentError) do
        OMQ::ZMTP::Mechanism::Curve.new(
          server_key: nil,
          public_key: nil,
          secret_key: nil,
        )
      end
    end
  end
end
