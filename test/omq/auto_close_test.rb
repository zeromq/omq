# frozen_string_literal: true

require_relative "../test_helper"

describe "auto-close" do
  before { OMQ::Transport::Inproc.reset! }

  it "closes TCP connections when the Async block exits" do
    connections = nil
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port
      push = OMQ::PUSH.connect("tcp://127.0.0.1:#{port}")
      wait_connected(push)

      push << "hello"
      assert_equal ["hello"], pull.receive

      connections = push.instance_variable_get(:@engine).connections.keys
      # no explicit close — Async block exits, tasks stopped, ensure blocks fire
    end

    connections.each do |conn|
      assert_raises(IOError, EOFError) { conn.receive_message }
    end
  end


  it "closes TCP server sockets when the Async block exits" do
    listeners = nil
    Async do
      pull = OMQ::PULL.bind("tcp://127.0.0.1:0")
      port = pull.last_tcp_port
      push = OMQ::PUSH.connect("tcp://127.0.0.1:#{port}")
      wait_connected(push)

      push << "hello"
      pull.receive

      listeners = pull.instance_variable_get(:@engine).instance_variable_get(:@listeners).dup
      # no explicit close
    end

    listeners.each_value do |l|
      l.servers.each do |server|
        assert server.closed?, "server socket should be closed"
      end
    end
  end


  it "is safe to call close explicitly after auto-close" do
    Async do
      push = OMQ::PUSH.new
      pull = OMQ::PULL.new
      push.bind("inproc://auto-close-idempotent")
      pull.connect("inproc://auto-close-idempotent")
      push << "hello"
      pull.receive

      push.close
      pull.close
      # Async block exits — task tree cleanup is idempotent
    end
  end


  it "delivers messages through inproc without explicit close" do
    Async do
      push = OMQ::PUSH.new
      pull = OMQ::PULL.new
      push.bind("inproc://auto-close-inproc")
      pull.connect("inproc://auto-close-inproc")

      10.times { |i| push << "msg-#{i}" }
      10.times { |i| assert_equal ["msg-#{i}"], pull.receive }
      # no explicit close
    end
  end
end
