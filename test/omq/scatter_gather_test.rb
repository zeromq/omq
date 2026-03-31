# frozen_string_literal: true

require_relative "../test_helper"

describe "SCATTER/GATHER over inproc" do
  before { OMQ::Transport::Inproc.reset! }

  it "sends and receives messages" do
    Async do
      gather  = OMQ::GATHER.bind("inproc://sg-1")
      scatter = OMQ::SCATTER.connect("inproc://sg-1")

      scatter.send("hello")
      msg = gather.receive
      assert_equal ["hello"], msg
    ensure
      scatter&.close
      gather&.close
    end
  end

  it "round-robins across multiple GATHER peers" do
    Async do
      g1 = OMQ::GATHER.bind("inproc://sg-rr-1")
      g2 = OMQ::GATHER.bind("inproc://sg-rr-2")

      scatter = OMQ::SCATTER.new
      scatter.connect("inproc://sg-rr-1")
      scatter.connect("inproc://sg-rr-2")

      scatter.send("msg1")
      scatter.send("msg2")

      assert_equal ["msg1"], g1.receive
      assert_equal ["msg2"], g2.receive
    ensure
      scatter&.close
      g1&.close
      g2&.close
    end
  end

  it "rejects multipart messages" do
    Async do
      gather  = OMQ::GATHER.bind("inproc://sg-mp")
      scatter = OMQ::SCATTER.connect("inproc://sg-mp")

      assert_raises(ArgumentError) { scatter.send(["part1", "part2"]) }
    ensure
      scatter&.close
      gather&.close
    end
  end
end
