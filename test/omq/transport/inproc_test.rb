# frozen_string_literal: true

require_relative "../../test_helper"

describe OMQ::Transport::Inproc do
  Inproc = OMQ::Transport::Inproc

  before { Inproc.reset! }

  describe "Pipe" do
    it "transfers messages bidirectionally" do
      Async do
        a_to_b = Async::Queue.new
        b_to_a = Async::Queue.new
        side_a = Inproc::Pipe.new(
          send_queue:    a_to_b,
          receive_queue: b_to_a,
          peer_identity: "",
          peer_type:     "PAIR",
        )
        side_b = Inproc::Pipe.new(
          send_queue:    b_to_a,
          receive_queue: a_to_b,
          peer_identity: "",
          peer_type:     "PAIR",
        )

        Async do
          side_a.send_message(["hello from A"])
          received = side_b.receive_message
          assert_equal ["hello from A"], received

          side_b.send_message(["hello from B"])
          received = side_a.receive_message
          assert_equal ["hello from B"], received
        end.wait
      end
    end

    it "copies data to avoid shared state" do
      Async do
        a_to_b = Async::Queue.new
        b_to_a = Async::Queue.new
        side_a = Inproc::Pipe.new(
          send_queue:    a_to_b,
          receive_queue: b_to_a,
          peer_identity: "",
          peer_type:     "PAIR",
        )
        side_b = Inproc::Pipe.new(
          send_queue:    b_to_a,
          receive_queue: a_to_b,
          peer_identity: "",
          peer_type:     "PAIR",
        )

        Async do
          original = "mutable".b.freeze
          side_a.send_message([original])

          received = side_b.receive_message
          assert_equal ["mutable"], received
          assert received.first.frozen?, "received part should be frozen"
        end.wait
      end
    end

    it "raises EOFError on receive after close" do
      Async do
        a_to_b = Async::Queue.new
        b_to_a = Async::Queue.new
        side_a = Inproc::Pipe.new(
          send_queue:    a_to_b,
          receive_queue: b_to_a,
          peer_identity: "",
          peer_type:     "PAIR",
        )
        side_b = Inproc::Pipe.new(
          send_queue:    b_to_a,
          receive_queue: a_to_b,
          peer_identity: "",
          peer_type:     "PAIR",
        )

        Async do
          side_a.close
          assert_raises(EOFError) { side_b.receive_message }
        end.wait
      end
    end

    it "raises IOError on send after close" do
      Async do
        a_to_b = Async::Queue.new
        side_a = Inproc::Pipe.new(
          send_queue:    a_to_b,
          receive_queue: Async::Queue.new,
          peer_identity: "",
          peer_type:     "PAIR",
        )

        Async do
          side_a.close
          assert_raises(IOError) { side_a.send_message(["data"]) }
        end.wait
      end
    end
  end
end
