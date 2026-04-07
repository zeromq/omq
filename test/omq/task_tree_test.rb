# frozen_string_literal: true

require_relative "../test_helper"

describe "Per-connection task tree" do
  # Regression: per-connection tasks (recv pump, heartbeat, reaper) were
  # spawned under @parent_task instead of the connection task. This meant
  # a finished @parent_task caused FinishedError on late connections, and
  # the task tree didn't match DESIGN.md.
  #
  # Fix: spawn_pump_task, start_recv_pump, and Heartbeat.start now use
  # Async::Task.current (the connection task) as the parent.

  def capture_hierarchy(task)
    lines = []
    task.traverse do |node, level|
      ann = node.respond_to?(:annotation) ? node.annotation : node.class.name
      lines << [level, ann.to_s]
    end
    lines
  end


  it "recv pump and heartbeat are children of the connection task" do
    Async do |task|
      pull = OMQ::PULL.new(nil, linger: 0)
      pull.heartbeat_interval = 1
      pull.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port

      push = OMQ::PUSH.new(nil, linger: 0)
      push.heartbeat_interval = 1
      push.connect("tcp://127.0.0.1:#{port}")
      wait_connected(push)

      push << "hello"
      assert_equal ["hello"], pull.receive

      hierarchy = capture_hierarchy(task)

      conn_level = hierarchy.find { |lvl, ann| ann.start_with?("conn ") }&.first
      refute_nil conn_level, "should have connection tasks"

      %w[recv\ pump heartbeat].each do |name|
        entries = hierarchy.select { |_, ann| ann == name }
        refute_empty entries, "should have #{name} tasks"
        entries.each do |lvl, _|
          assert lvl > conn_level,
            "#{name} should be a child of conn task (level #{lvl} > #{conn_level})"
        end
      end
    ensure
      push&.close
      pull&.close
    end
  end


  it "reaper is a child of the connection task on PUSH" do
    Async do |task|
      push = OMQ::PUSH.new(nil, linger: 0)
      push.bind("tcp://127.0.0.1:0")
      port = push.last_tcp_port

      pull = OMQ::PULL.new(nil, linger: 0)
      pull.connect("tcp://127.0.0.1:#{port}")
      wait_connected(pull)

      push << "hello"
      assert_equal ["hello"], pull.receive

      hierarchy = capture_hierarchy(task)

      conn_level = hierarchy.find { |lvl, ann| ann.start_with?("conn ") }&.first
      refute_nil conn_level, "should have connection tasks"

      reaper_entries = hierarchy.select { |_, ann| ann == "reaper" }
      refute_empty reaper_entries, "PUSH should have a reaper task"
      reaper_entries.each do |lvl, _|
        assert lvl > conn_level,
          "reaper should be a child of conn task (level #{lvl} > #{conn_level})"
      end
    ensure
      pull&.close
      push&.close
    end
  end
end
