# frozen_string_literal: true

require_relative "../test_helper"

# Disconnect-then-reconnect must work for ALL socket types.
# The connecting side detects peer loss and auto-reconnects.
#
describe "Reconnect after server restart" do

  # Helper: connect side reconnects after bind side restarts on same port.
  #
  def assert_reconnects(bind_class, connect_class, port: nil, &exchange)
    Async do
      server = bind_class.new(nil, linger: 0)
      server.bind("tcp://127.0.0.1:0")
      port = server.last_tcp_port

      client = connect_class.new(nil, linger: 0)
      client.reconnect_interval = 0.02
      client.connect("tcp://127.0.0.1:#{port}")
      sleep 0.02

      # First exchange
      exchange.call(client, server)

      # Kill server
      server.close
      sleep 0.03

      # Restart on same port
      server2 = bind_class.new(nil, linger: 0)
      server2.bind("tcp://127.0.0.1:#{port}")
      sleep 0.05

      # Second exchange after reconnect
      exchange.call(client, server2)
    ensure
      client&.close
      server2&.close
    end
  end

  # ── Classic socket types ──────────────────────────────────────────

  it "REQ/REP" do
    assert_reconnects(OMQ::REP, OMQ::REQ) do |req, rep|
      req.send("ping")
      assert_equal ["ping"], rep.receive
      rep.send("pong")
      assert_equal ["pong"], req.receive
    end
  end

  it "PUSH/PULL" do
    assert_reconnects(OMQ::PULL, OMQ::PUSH) do |push, pull|
      push.send("data")
      assert_equal ["data"], pull.receive
    end
  end

  it "DEALER/REP" do
    assert_reconnects(OMQ::REP, OMQ::DEALER) do |dealer, rep|
      dealer.send(["", "request"])
      assert_equal ["request"], rep.receive
      rep.send("reply")
      msg = dealer.receive
      assert_includes msg, "reply"
    end
  end

  it "PUB/SUB" do
    Async do
      pub = OMQ::PUB.new(nil, linger: 0)
      pub.bind("tcp://127.0.0.1:0")
      port = pub.last_tcp_port

      sub = OMQ::SUB.new(nil, linger: 0)
      sub.reconnect_interval = 0.02
      sub.connect("tcp://127.0.0.1:#{port}")
      sub.subscribe("")
      sleep 0.02

      pub.send("first")
      assert_equal ["first"], sub.receive

      pub.close
      sleep 0.03

      pub2 = OMQ::PUB.new(nil, linger: 0)
      pub2.bind("tcp://127.0.0.1:#{port}")
      sleep 0.05

      pub2.send("second")
      assert_equal ["second"], sub.receive
    ensure
      sub&.close
      pub2&.close
    end
  end

  it "PAIR" do
    assert_reconnects(OMQ::PAIR, OMQ::PAIR) do |client, server|
      client.send("hello")
      assert_equal ["hello"], server.receive
    end
  end

  # ── Draft socket types ────────────────────────────────────────────

  it "SCATTER/GATHER" do
    assert_reconnects(OMQ::GATHER, OMQ::SCATTER) do |scatter, gather|
      scatter.send("task")
      assert_equal ["task"], gather.receive
    end
  end

  it "CHANNEL" do
    assert_reconnects(OMQ::CHANNEL, OMQ::CHANNEL) do |client, server|
      client.send("msg")
      assert_equal ["msg"], server.receive
    end
  end

  it "CLIENT/SERVER" do
    Async do
      server = OMQ::SERVER.new(nil, linger: 0)
      server.bind("tcp://127.0.0.1:0")
      port = server.last_tcp_port

      client = OMQ::CLIENT.new(nil, linger: 0)
      client.reconnect_interval = 0.02
      client.connect("tcp://127.0.0.1:#{port}")
      sleep 0.02

      client.send("req1")
      msg = server.receive
      assert_equal "req1", msg[1]
      server.send_to(msg[0], "rep1")
      assert_equal ["rep1"], client.receive

      server.close
      sleep 0.03

      server2 = OMQ::SERVER.new(nil, linger: 0)
      server2.bind("tcp://127.0.0.1:#{port}")
      sleep 0.05

      client.send("req2")
      msg = server2.receive
      assert_equal "req2", msg[1]
    ensure
      client&.close
      server2&.close
    end
  end

  it "RADIO/DISH" do
    Async do
      radio = OMQ::RADIO.new(nil, linger: 0)
      radio.bind("tcp://127.0.0.1:0")
      port = radio.last_tcp_port

      dish = OMQ::DISH.new(nil, linger: 0)
      dish.reconnect_interval = 0.02
      dish.connect("tcp://127.0.0.1:#{port}")
      dish.join("g")
      sleep 0.02

      radio.publish("g", "first")
      assert_equal ["g", "first"], dish.receive

      radio.close
      sleep 0.03

      radio2 = OMQ::RADIO.new(nil, linger: 0)
      radio2.bind("tcp://127.0.0.1:#{port}")
      sleep 0.05

      radio2.publish("g", "second")
      assert_equal ["g", "second"], dish.receive
    ensure
      dish&.close
      radio2&.close
    end
  end

  it "PEER" do
    Async do
      a = OMQ::PEER.new(nil, linger: 0)
      a.bind("tcp://127.0.0.1:0")
      port = a.last_tcp_port

      b = OMQ::PEER.new(nil, linger: 0)
      b.reconnect_interval = 0.02
      b.connect("tcp://127.0.0.1:#{port}")
      sleep 0.02

      # a knows b's routing_id
      routing = a.instance_variable_get(:@engine).routing
      b_id = routing.instance_variable_get(:@connections_by_routing_id).keys.first
      a.send_to(b_id, "hello")
      msg = b.receive
      assert_equal "hello", msg[1]

      a.close
      sleep 0.03

      a2 = OMQ::PEER.new(nil, linger: 0)
      a2.bind("tcp://127.0.0.1:#{port}")
      sleep 0.05

      routing2 = a2.instance_variable_get(:@engine).routing
      b_id2 = routing2.instance_variable_get(:@connections_by_routing_id).keys.first
      a2.send_to(b_id2, "reconnected")
      msg = b.receive
      assert_equal "reconnected", msg[1]
    ensure
      b&.close
      a2&.close
    end
  end
end
