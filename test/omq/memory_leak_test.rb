# frozen_string_literal: true

require_relative "../test_helper"

describe "inproc memory leaks" do
  before { OMQ::ZMTP::Transport::Inproc.reset! }

  it "does not leak DirectPipe objects after close" do
    Async do
      GC.start
      before = ObjectSpace.each_object(OMQ::ZMTP::Transport::Inproc::DirectPipe).count

      push = pull = nil
      10.times do |i|
        push = OMQ::PUSH.new
        pull = OMQ::PULL.new
        push.bind("inproc://leak-test-#{i}")
        pull.connect("inproc://leak-test-#{i}")
        push << "hello"
        pull.receive
        push.close
        pull.close
      end
      push = pull = nil

      GC.start
      GC.start
      after = ObjectSpace.each_object(OMQ::ZMTP::Transport::Inproc::DirectPipe).count

      assert_equal 0, after - before, "leaked #{after - before} DirectPipe objects"
    end
  end


  it "does not leak connections after both sides close" do
    Async do
      10.times do |i|
        push = OMQ::PUSH.new
        pull = OMQ::PULL.new
        push.bind("inproc://leak-cycle-#{i}")
        pull.connect("inproc://leak-cycle-#{i}")
        push << "msg"
        pull.receive
        push.close
        pull.close
      end

      GC.start
      GC.start
      conns = ObjectSpace.each_object(OMQ::ZMTP::Transport::Inproc::DirectPipe).count
      assert_equal 0, conns, "leaked #{conns} DirectPipe objects"
    end
  end


  it "cleans up the inproc registry after unbind" do
    Async do
      10.times do |i|
        ep = "inproc://leak-registry-#{i}"
        push = OMQ::PUSH.new
        push.bind(ep)
        push.close
      end

      registry = OMQ::ZMTP::Transport::Inproc.instance_variable_get(:@registry)
      assert_equal 0, registry.size, "leaked #{registry.size} registry entries"
    end
  end


  it "does not grow engine task lists over many messages" do
    Async do
      push = OMQ::PUSH.new
      pull = OMQ::PULL.new
      push.bind("inproc://leak-tasks")
      pull.connect("inproc://leak-tasks")

      1000.times { |i| push << "msg-#{i}" }
      1000.times { pull.receive }

      push_tasks = push.instance_variable_get(:@engine).instance_variable_get(:@tasks)
      pull_tasks = pull.instance_variable_get(:@engine).instance_variable_get(:@tasks)

      # Tasks should be bounded — not one per message
      assert push_tasks.size < 10, "push has #{push_tasks.size} tasks"
      assert pull_tasks.size < 10, "pull has #{pull_tasks.size} tasks"
    ensure
      push&.close
      pull&.close
    end
  end
end
