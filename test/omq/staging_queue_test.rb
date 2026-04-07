# frozen_string_literal: true

require_relative "../test_helper"

describe OMQ::Routing::StagingQueue do
  def build(max = nil)
    OMQ::Routing::StagingQueue.new(max)
  end

  describe "#enqueue / #dequeue" do
    it "returns messages in FIFO order" do
      q = build
      q.enqueue("a")
      q.enqueue("b")
      q.enqueue("c")
      assert_equal "a", q.dequeue
      assert_equal "b", q.dequeue
      assert_equal "c", q.dequeue
    end

    it "returns nil when empty" do
      assert_nil build.dequeue
    end
  end

  describe "#prepend" do
    it "is dequeued before main queue items" do
      q = build
      q.enqueue("a")
      q.enqueue("b")
      q.prepend("z")
      assert_equal "z", q.dequeue
      assert_equal "a", q.dequeue
      assert_equal "b", q.dequeue
    end

    it "preserves prepend order (first prepend = first out)" do
      q = build
      q.enqueue("a")
      q.prepend("y")
      q.prepend("z")
      # head = [y, z], main = [a]
      assert_equal "y", q.dequeue
      assert_equal "z", q.dequeue
      assert_equal "a", q.dequeue
    end
  end

  describe "#empty?" do
    it "is true when both head and main are empty" do
      assert build.empty?
    end

    it "is false when main has items" do
      q = build
      q.enqueue("a")
      refute q.empty?
    end

    it "is false when head has items" do
      q = build
      q.prepend("z")
      refute q.empty?
    end

    it "becomes true after draining both" do
      q = build
      q.enqueue("a")
      q.prepend("z")
      q.dequeue
      q.dequeue
      assert q.empty?
    end
  end

  describe "bounded" do
    it "blocks on enqueue when at capacity" do
      Async do
        q = build(1)
        q.enqueue("a")

        filled = false
        task = Async::Task.current.async do
          q.enqueue("b")
          filled = true
        end

        # yield to let the enqueue attempt run — it should block
        Async::Task.current.yield
        refute filled, "enqueue should block when queue is full"

        # drain one — unblocks the writer
        assert_equal "a", q.dequeue
        task.wait
        assert filled
        assert_equal "b", q.dequeue
      end
    end
  end

  describe "unbounded (max=nil)" do
    it "never blocks" do
      q = build(nil)
      100.times { |i| q.enqueue(i) }
      100.times { |i| assert_equal i, q.dequeue }
      assert q.empty?
    end
  end
end
