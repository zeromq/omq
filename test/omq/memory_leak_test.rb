# frozen_string_literal: true

require_relative "../test_helper"
require "weakref"

describe "inproc memory leaks" do
  before { OMQ::Transport::Inproc.reset! }

  # Collect until a WeakRef is dead, or give up after max attempts.
  #
  def gc_until_collected(weak, max: 20)
    max.times do
      return true unless weak.weakref_alive?
      GC.start(full_mark: true, immediate_sweep: true)
      GC.compact if GC.respond_to?(:compact)
    end
    !weak.weakref_alive?
  end

  it "does not leak DirectPipe objects after close" do
    weak = nil
    Async do
      push = OMQ::PUSH.new
      pull = OMQ::PULL.new
      push.bind("inproc://leak-test")
      pull.connect("inproc://leak-test")
      push << "hello"
      pull.receive

      # Track one of the pipes
      pipe = push.instance_variable_get(:@engine).connections.first
      weak = WeakRef.new(pipe)
      pipe = nil

      push.close
      pull.close
    end

    assert gc_until_collected(weak), "DirectPipe was not collected after close"
  end


  it "does not leak connections after both sides close" do
    weak = nil
    Async do
      push = OMQ::PUSH.new
      pull = OMQ::PULL.new
      push.bind("inproc://leak-cycle")
      pull.connect("inproc://leak-cycle")
      push << "msg"
      pull.receive

      pipe = pull.instance_variable_get(:@engine).connections.first
      weak = WeakRef.new(pipe)
      pipe = nil

      push.close
      pull.close
    end

    assert gc_until_collected(weak), "DirectPipe was not collected after close"
  end


  it "cleans up the inproc registry after unbind" do
    Async do
      10.times do |i|
        ep = "inproc://leak-registry-#{i}"
        push = OMQ::PUSH.new
        push.bind(ep)
        push.close
      end

      registry = OMQ::Transport::Inproc.instance_variable_get(:@registry)
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
