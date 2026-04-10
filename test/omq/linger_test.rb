# frozen_string_literal: true

require_relative "../test_helper"

describe "Linger" do
  it "drains send queue before closing when linger > 0" do
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port

      push = OMQ::PUSH.new(nil, linger: 1)
      push.connect("tcp://127.0.0.1:#{port}")

      # Send several messages
      5.times { |i| push.send("msg-#{i}") }

      # Close with linger — should wait for messages to drain
      push.close

      # All messages should have been delivered
      5.times do |i|
        msg = pull.receive
        assert_equal ["msg-#{i}"], msg
      end
    ensure
      pull&.close
    end
  end

  it "closes immediately when linger = 0" do
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port

      push = OMQ::PUSH.new(nil, linger: 0)
      push.connect("tcp://127.0.0.1:#{port}")

      push.send("before close")

      # Close immediately — some messages may be lost
      elapsed = Async::Clock.measure do
        push.close
      end

      # Close should be near-instant (< 100ms)
      assert_operator elapsed, :<, 0.1
    ensure
      pull&.close
    end
  end

  it "reconnects during linger to deliver queued messages" do
    Async do
      # Grab a free port by binding temporarily
      tmp = TCPServer.new("127.0.0.1", 0)
      port = tmp.local_address.ip_port
      tmp.close

      push = OMQ::PUSH.new(nil, linger: 5)
      push.reconnect_interval = RECONNECT_INTERVAL
      push.connect("tcp://127.0.0.1:#{port}")

      # Send while no peer is listening — message queues
      push.send("early")

      # Bind after a delay — reconnect should find it during linger
      sleep 0.02
      pull = OMQ::PULL.bind("tcp://127.0.0.1:#{port}")

      # Close push — linger should drain the queued message
      push.close

      pull.recv_timeout = 2
      msg = pull.receive
      assert_equal ["early"], msg
    ensure
      pull&.close
    end
  end

  it "delivers multiple messages when peer appears during linger period" do
    Async do
      tmp = TCPServer.new("127.0.0.1", 0)
      port = tmp.local_address.ip_port
      tmp.close

      push = OMQ::PUSH.new(nil, linger: 5)
      push.reconnect_interval = RECONNECT_INTERVAL
      push.connect("tcp://127.0.0.1:#{port}")

      3.times { |i| push.send("msg-#{i}") }

      # Start close in a separate task — it will block during linger
      closer = Async { push.close }

      # Bind while close is draining
      sleep 0.02
      pull = OMQ::PULL.bind("tcp://127.0.0.1:#{port}")

      closer.wait

      pull.recv_timeout = 2
      received = []
      3.times { received << pull.receive.first }
      assert_equal ["msg-0", "msg-1", "msg-2"], received
    ensure
      pull&.close
    end
  end

  it "drains in-flight messages across multiple peers before closing" do
    Async do
      pull_a = OMQ::PULL.bind("tcp://127.0.0.1:0")
      pull_b = OMQ::PULL.bind("tcp://127.0.0.1:0")

      push = OMQ::PUSH.new(nil, linger: 5)
      push.connect("tcp://127.0.0.1:#{pull_a.last_tcp_port}")
      push.connect("tcp://127.0.0.1:#{pull_b.last_tcp_port}")

      # Wait for both peers so pumps exist for both connections.
      sleep 0.001 until push.connection_count >= 2

      # Large messages (64KB each) force IO yields during write_batch,
      # opening a window where pump fibers have dequeued messages but
      # haven't flushed them yet. This is the race condition:
      # drain_send_queues sees an empty queue while pumps hold in-flight
      # batches, proceeds to tear_down_barrier, and kills them.
      n       = 20
      payload = "X" * 65_536
      n.times { |i| push.send(["#{i}:#{payload}"]) }
      push.close

      # Collect from both pulls — every message must arrive.
      pull_a.recv_timeout = 2
      pull_b.recv_timeout = 2
      received = []
      barrier  = Async::Barrier.new
      [pull_a, pull_b].each do |pull|
        barrier.async do
          loop do
            msg = pull.receive
            received << msg.first.split(":").first.to_i
          rescue IO::TimeoutError
            break
          end
        end
      end
      barrier.wait

      assert_equal n, received.size, "expected all #{n} messages delivered, got #{received.size}"
    ensure
      pull_a&.close
      pull_b&.close
    end
  end

  it "actually delivers all messages before close completes over TCP" do
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port

      push = OMQ::PUSH.new(nil, linger: 2)
      push.connect("tcp://127.0.0.1:#{port}")
      wait_connected(push, pull)

      20.times { |i| push.send("drain-#{i}") }
      push.close

      received = []
      20.times do
        pull.recv_timeout = 1
        received << pull.receive.first
      end

      assert_equal 20, received.size
      assert_equal "drain-0", received.first
      assert_equal "drain-19", received.last
    ensure
      pull&.close
    end
  end
end
