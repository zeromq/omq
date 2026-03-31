# frozen_string_literal: true

require_relative "../../test_helper"
require "socket"
require "io/stream"

describe Protocol::ZMTP::Connection do
  Connection = Protocol::ZMTP::Connection

  # Use a Unix socket pair for testing ZMTP framing (no inproc pipe needed)
  def make_socketpair
    UNIXSocket.pair.map { |s| IO::Stream::Buffered.wrap(s) }
  end

  describe "#handshake!" do
    it "completes NULL handshake between compatible types" do
      Async do
        client_io, server_io = make_socketpair

        client = Connection.new(client_io, socket_type: "REQ", as_server: false)
        server = Connection.new(server_io, socket_type: "REP", as_server: true)

        client_task = Async { client.handshake! }
        server_task = Async { server.handshake! }

        client_task.wait
        server_task.wait

        assert_equal "REP", client.peer_socket_type
        assert_equal "REQ", server.peer_socket_type
        assert_equal "", client.peer_identity
        assert_equal "", server.peer_identity
      ensure
        client_io&.close
        server_io&.close
      end
    end

    it "exchanges identity" do
      Async do
        client_io, server_io = make_socketpair

        client = Connection.new(client_io, socket_type: "DEALER", identity: "client-1", as_server: false)
        server = Connection.new(server_io, socket_type: "ROUTER", identity: "server-1", as_server: true)

        client_task = Async { client.handshake! }
        server_task = Async { server.handshake! }

        client_task.wait
        server_task.wait

        assert_equal "client-1", server.peer_identity
        assert_equal "server-1", client.peer_identity
      ensure
        client_io&.close
        server_io&.close
      end
    end

    it "raises on incompatible socket types" do
      Async do
        client_io, server_io = make_socketpair

        client = Connection.new(client_io, socket_type: "REQ", as_server: false)
        server = Connection.new(server_io, socket_type: "PUB", as_server: true)

        client_task = Async { client.handshake! }
        server_task = Async { server.handshake! }

        errors = []
        begin
          client_task.wait
        rescue Protocol::ZMTP::Error => e
          errors << e
        end
        begin
          server_task.wait
        rescue Protocol::ZMTP::Error => e
          errors << e
        end

        refute_empty errors
      ensure
        client_io&.close
        server_io&.close
      end
    end

    it "works for all valid socket type pairs" do
      valid_pairs = [
        %w[PAIR PAIR],
        %w[REQ REP],
        %w[REQ ROUTER],
        %w[DEALER REP],
        %w[DEALER DEALER],
        %w[DEALER ROUTER],
        %w[ROUTER ROUTER],
        %w[PUB SUB],
        %w[PUB XSUB],
        %w[XPUB SUB],
        %w[XPUB XSUB],
        %w[PUSH PULL],
      ]

      valid_pairs.each do |type_a, type_b|
        Async do
          io_a, io_b = make_socketpair
          conn_a = Connection.new(io_a, socket_type: type_a)
          conn_b = Connection.new(io_b, socket_type: type_b)

          task_a = Async { conn_a.handshake! }
          task_b = Async { conn_b.handshake! }

          task_a.wait
          task_b.wait

          assert_equal type_b, conn_a.peer_socket_type, "#{type_a} should see #{type_b}"
          assert_equal type_a, conn_b.peer_socket_type, "#{type_b} should see #{type_a}"
        ensure
          io_a&.close
          io_b&.close
        end
      end
    end
  end

  describe "#send_message / #receive_message" do
    it "sends and receives single-frame messages" do
      Async do
        io_a, io_b = make_socketpair
        conn_a = Connection.new(io_a, socket_type: "PAIR")
        conn_b = Connection.new(io_b, socket_type: "PAIR")

        [Async { conn_a.handshake! }, Async { conn_b.handshake! }].each(&:wait)

        Async { conn_a.send_message(["hello"]) }
        msg = nil
        Async { msg = conn_b.receive_message }.wait

        assert_equal ["hello"], msg
      ensure
        io_a&.close
        io_b&.close
      end
    end

    it "sends and receives multi-frame messages" do
      Async do
        io_a, io_b = make_socketpair
        conn_a = Connection.new(io_a, socket_type: "PAIR")
        conn_b = Connection.new(io_b, socket_type: "PAIR")

        [Async { conn_a.handshake! }, Async { conn_b.handshake! }].each(&:wait)

        Async { conn_a.send_message(["frame1", "frame2", "frame3"]) }
        msg = nil
        Async { msg = conn_b.receive_message }.wait

        assert_equal ["frame1", "frame2", "frame3"], msg
      ensure
        io_a&.close
        io_b&.close
      end
    end

    it "handles binary data" do
      Async do
        io_a, io_b = make_socketpair
        conn_a = Connection.new(io_a, socket_type: "PAIR")
        conn_b = Connection.new(io_b, socket_type: "PAIR")

        [Async { conn_a.handshake! }, Async { conn_b.handshake! }].each(&:wait)

        binary = (0..255).map(&:chr).join.b
        Async { conn_a.send_message([binary]) }
        msg = nil
        Async { msg = conn_b.receive_message }.wait

        assert_equal [binary], msg
      ensure
        io_a&.close
        io_b&.close
      end
    end
  end
end
