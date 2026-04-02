# frozen_string_literal: true

require_relative "../../../test_helper"
require "localhost"

describe "TLS transport" do
  let(:authority) { Localhost::Authority.fetch }

  def server_context
    authority.server_context.tap do |ctx|
      ctx.min_version = OpenSSL::SSL::TLS1_3_VERSION
    end
  end

  def client_context
    authority.client_context.tap do |ctx|
      ctx.min_version = OpenSSL::SSL::TLS1_3_VERSION
    end
  end

  it "PAIR over tls+tcp with ephemeral port" do
    Async do
      server = OMQ::PAIR.new
      server.tls_context = server_context
      server.bind("tls+tcp://localhost:0")
      port = server.last_tcp_port
      refute_nil port
      assert port > 0

      client = OMQ::PAIR.new
      client.tls_context = client_context
      client.connect("tls+tcp://localhost:#{port}")

      client.send("hello tls")
      msg = server.receive
      assert_equal ["hello tls"], msg

      server.send("reply tls")
      msg = client.receive
      assert_equal ["reply tls"], msg
    ensure
      client&.close
      server&.close
    end
  end

  it "REQ/REP over tls+tcp" do
    Async do
      rep = OMQ::REP.new
      rep.tls_context = server_context
      rep.bind("tls+tcp://localhost:0")
      port = rep.last_tcp_port

      req = OMQ::REQ.new
      req.tls_context = client_context
      req.connect("tls+tcp://localhost:#{port}")

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

  it "PUSH/PULL over tls+tcp" do
    Async do
      pull = OMQ::PULL.new
      pull.tls_context = server_context
      pull.bind("tls+tcp://localhost:0")
      port = pull.last_tcp_port

      push = OMQ::PUSH.new
      push.tls_context = client_context
      push.connect("tls+tcp://localhost:#{port}")

      push.send("pipeline msg")
      msg = pull.receive
      assert_equal ["pipeline msg"], msg
    ensure
      push&.close
      pull&.close
    end
  end

  it "raises ArgumentError without tls_context" do
    Async do
      server = OMQ::PAIR.new
      assert_raises(ArgumentError) { server.bind("tls+tcp://localhost:0") }
    ensure
      server&.close
    end
  end

  it "freezes the tls_context on first use" do
    Async do
      server = OMQ::PAIR.new
      ctx = server_context
      refute ctx.frozen?
      server.tls_context = ctx
      server.bind("tls+tcp://localhost:0")
      assert ctx.frozen?
    ensure
      server&.close
    end
  end

  it "drops connections with bad certificates" do
    Async do
      server = OMQ::PAIR.new
      server.tls_context = server_context
      server.bind("tls+tcp://localhost:0")
      port = server.last_tcp_port

      # Client uses a context that doesn't trust the server's CA
      bad_ctx = OpenSSL::SSL::SSLContext.new
      bad_ctx.min_version = OpenSSL::SSL::TLS1_3_VERSION
      bad_ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER

      # Raw TCP connect + TLS handshake should fail
      tcp = TCPSocket.new("localhost", port)
      ssl = OpenSSL::SSL::SSLSocket.new(tcp, bad_ctx)
      ssl.sync_close = true
      ssl.hostname   = "localhost"
      assert_raises(OpenSSL::SSL::SSLError) { ssl.connect }
      ssl.close rescue nil

      # Server accept loop should still be alive — test with a good client
      client = OMQ::PAIR.new
      client.tls_context = client_context
      client.connect("tls+tcp://localhost:#{port}")

      client.send("after bad cert")
      msg = server.receive
      assert_equal ["after bad cert"], msg
    ensure
      client&.close
      server&.close
    end
  end
end
