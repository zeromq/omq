# frozen_string_literal: true

require_relative "../test_helper"

describe "Socket#bind / #connect parent: kwarg" do
  it "places socket tasks under a caller-provided Async::Barrier" do
    Async do |task|
      user_barrier = Async::Barrier.new

      pull = OMQ::PULL.new(nil, linger: 0)
      pull.bind("tcp://127.0.0.1:0", parent: user_barrier)
      port = pull.last_tcp_port

      push = OMQ::PUSH.new(nil, linger: 0)
      push.connect("tcp://127.0.0.1:#{port}", parent: user_barrier)
      wait_connected(push)

      push << "hello"
      assert_equal ["hello"], pull.receive

      # Every OMQ task for either socket must now be tracked by the
      # user-provided barrier. Socket internals spawn via
      # socket_barrier.async(parent: user_barrier), which delegates to
      # user_barrier.async and also records the task on the socket
      # barrier. So user_barrier.tasks should cover at least the two
      # socket-level barriers' worth of children.
      refute_empty user_barrier.instance_variable_get(:@tasks),
                   "user barrier should be tracking OMQ socket tasks"
    ensure
      push&.close
      pull&.close
    end
  end


  it "cascades teardown when the user-provided barrier is stopped" do
    Async do |task|
      user_barrier = Async::Barrier.new

      pull = OMQ::PULL.new(nil, linger: 0)
      pull.bind("tcp://127.0.0.1:0", parent: user_barrier)
      port = pull.last_tcp_port

      push = OMQ::PUSH.new(nil, linger: 0)
      push.connect("tcp://127.0.0.1:#{port}", parent: user_barrier)
      wait_connected(push)

      push << "ping"
      assert_equal ["ping"], pull.receive

      # Stopping the user's barrier should cascade through both
      # sockets' internal barriers and take down every pump, reaper,
      # supervisor, etc. Afterwards the sockets are effectively dead —
      # #close still completes cleanly (idempotent teardown).
      user_barrier.stop

      push.close
      pull.close
    end
  end


  it "only the first bind/connect captures the parent (idempotent)" do
    Async do |task|
      first  = Async::Barrier.new
      second = Async::Barrier.new

      pull = OMQ::PULL.new(nil, linger: 0)
      pull.bind("tcp://127.0.0.1:0", parent: first)
      port = pull.last_tcp_port

      # Second capture attempt with a different parent — silently ignored.
      push = OMQ::PUSH.new(nil, linger: 0)
      push.connect("tcp://127.0.0.1:#{port}", parent: first)
      # A later call on the same socket with a different parent is a no-op.
      push.connect("tcp://127.0.0.1:#{port}", parent: second)

      wait_connected(push)

      # `second` never had any tasks put under it.
      assert_empty second.instance_variable_get(:@tasks),
                   "second barrier must not have captured any OMQ tasks"
    ensure
      push&.close
      pull&.close
    end
  end
end
