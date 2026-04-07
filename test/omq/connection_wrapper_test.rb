# frozen_string_literal: true

require_relative "../test_helper"

describe "Engine connection_wrapper" do
  before { OMQ::Transport::Inproc.reset! }

  it "wraps inproc connections via connection_ready" do
    Async do
      pull = OMQ::PULL.bind("inproc://cw-inproc")

      wrapped = []
      pull.instance_variable_get(:@engine).connection_wrapper = ->(conn) do
        wrapped << conn.class.name
        conn
      end

      push = OMQ::PUSH.connect("inproc://cw-inproc")
      wait_connected(push)

      push << "hello"
      assert_equal ["hello"], pull.receive
      assert_equal 1, wrapped.size
      assert_match(/DirectPipe/, wrapped.first)
    ensure
      [push, pull].compact.each(&:close)
    end
  end


  it "wraps IPC connections via setup_connection" do
    Async do
      pull = OMQ::PULL.bind("ipc://@omq-test-cw-ipc")

      wrapped = []
      pull.instance_variable_get(:@engine).connection_wrapper = ->(conn) do
        wrapped << conn.class.name
        conn
      end

      push = OMQ::PUSH.connect("ipc://@omq-test-cw-ipc")
      wait_connected(push)

      push << "hello"
      assert_equal ["hello"], pull.receive
      assert_equal 1, wrapped.size
      assert_match(/Connection/, wrapped.first)
    ensure
      [push, pull].compact.each(&:close)
    end
  end


  it "wraps TCP connections via setup_connection" do
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")

      wrapped = []
      pull.instance_variable_get(:@engine).connection_wrapper = ->(conn) do
        wrapped << conn.class.name
        conn
      end

      push = OMQ::PUSH.connect(pull.last_endpoint)
      wait_connected(push)

      push << "hello"
      assert_equal ["hello"], pull.receive
      assert_equal 1, wrapped.size
      assert_match(/Connection/, wrapped.first)
    ensure
      [push, pull].compact.each(&:close)
    end
  end


  it "wrapper can transform messages on send (IPC)" do
    Async do
      pull = OMQ::PULL.bind("ipc://@omq-test-cw-transform")

      push = OMQ::PUSH.new

      # Wrapper that upcases all sent messages
      upcaser = Class.new(SimpleDelegator) do
        def send_message(parts)
          super(parts.map(&:upcase))
        end

        def write_message(parts)
          super(parts.map(&:upcase))
        end

        def is_a?(klass)
          super || __getobj__.is_a?(klass)
        end
      end

      push.instance_variable_get(:@engine).connection_wrapper = ->(conn) do
        upcaser.new(conn)
      end

      push.connect("ipc://@omq-test-cw-transform")
      wait_connected(push)

      push << "hello"
      assert_equal ["HELLO"], pull.receive
    ensure
      [push, pull].compact.each(&:close)
    end
  end


  it "nil wrapper leaves connections unwrapped" do
    Async do
      pull = OMQ::PULL.bind("inproc://cw-nil")
      # connection_wrapper defaults to nil
      assert_nil pull.instance_variable_get(:@engine).connection_wrapper

      push = OMQ::PUSH.connect("inproc://cw-nil")
      wait_connected(push)

      push << "hello"
      assert_equal ["hello"], pull.receive
    ensure
      [push, pull].compact.each(&:close)
    end
  end


  it "recv pump skips byte counting for wrapped connections returning mixed arrays" do
    Async do
      pull = OMQ::PULL.bind("ipc://@omq-test-cw-mixed-array")

      # Wrapper that returns [String, Integer] — an Array whose first
      # element is a String but second is not. Without instance_of?-based
      # byte counting this would crash on Integer#bytesize.
      wrapper = Class.new(SimpleDelegator) do
        def receive_message
          parts = super
          [parts.first, parts.first.length]
        end

        def is_a?(klass) = super || __getobj__.is_a?(klass)
      end

      pull.instance_variable_get(:@engine).connection_wrapper = ->(conn) do
        wrapper.new(conn)
      end

      push = OMQ::PUSH.connect("ipc://@omq-test-cw-mixed-array")
      wait_connected(push)

      5.times { |i| push << "msg-#{i}" }
      results = 5.times.map { pull.receive }

      assert_equal 5, results.size
      results.each_with_index do |r, i|
        assert_equal "msg-#{i}", r.first
        assert_equal "msg-#{i}".length, r.last
      end
    ensure
      [push, pull].compact.each(&:close)
    end
  end


  it "recv pump fairness handles non-string messages" do
    Async do
      pull = OMQ::PULL.bind("ipc://@omq-test-cw-fairness")

      # Wrapper that makes receive_message return a Hash instead of string array
      deserializer = Class.new(SimpleDelegator) do
        def receive_message
          parts = super
          { data: parts.first }
        end

        def is_a?(klass)
          super || __getobj__.is_a?(klass)
        end
      end

      pull.instance_variable_get(:@engine).connection_wrapper = ->(conn) do
        deserializer.new(conn)
      end

      push = OMQ::PUSH.connect("ipc://@omq-test-cw-fairness")
      wait_connected(push)

      # Send multiple messages — the fairness byte counting must not crash
      # on non-string messages
      5.times { |i| push << "msg-#{i}" }
      results = 5.times.map { pull.receive }

      assert_equal 5, results.size
      results.each_with_index do |r, i|
        assert_equal({ data: "msg-#{i}" }, r)
      end
    ensure
      [push, pull].compact.each(&:close)
    end
  end
end
