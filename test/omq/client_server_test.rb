# frozen_string_literal: true

require_relative "../test_helper"

describe "CLIENT/SERVER over inproc" do
  before { OMQ::Transport::Inproc.reset! }

  it "server receives and routes reply to correct client" do
    Async do
      server = OMQ::SERVER.bind("inproc://cs-1")

      client1 = OMQ::CLIENT.connect("inproc://cs-1")
      client2 = OMQ::CLIENT.connect("inproc://cs-1")

      client1.send("from client1")
      msg = server.receive
      routing_id = msg[0]
      assert_equal "from client1", msg[1]

      server.send_to(routing_id, "reply to client1")
      reply = client1.receive
      assert_equal ["reply to client1"], reply
    ensure
      client1&.close
      client2&.close
      server&.close
    end
  end

  it "rejects multipart messages" do
    Async do
      server = OMQ::SERVER.bind("inproc://cs-mp")
      client = OMQ::CLIENT.connect("inproc://cs-mp")

      assert_raises(ArgumentError) { client.send(["part1", "part2"]) }
    ensure
      client&.close
      server&.close
    end
  end
end
