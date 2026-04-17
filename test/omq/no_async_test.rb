# frozen_string_literal: true

require_relative "../test_helper"

describe "non-Async usage" do
  before { OMQ::Transport::Inproc.reset! }

  it "sends and receives without an Async block" do
    pull = OMQ::PULL.new
    port = pull.bind("tcp://127.0.0.1:0").port
    push = OMQ::PUSH.connect("tcp://127.0.0.1:#{port}")

    push << "hello"
    assert_equal ["hello"], pull.receive
  ensure
    push&.close
    pull&.close
  end


  it "unregisters linger when a socket is closed before shutdown" do
    # skip 'non-Async seems broken'
    a = OMQ::PUSH.new.tap { |s| s.linger = 0 }
    b = OMQ::PUSH.new.tap { |s| s.linger = 0 }
    a.bind("tcp://127.0.0.1:0")
    b.bind("tcp://127.0.0.1:0")

    lingers = OMQ::Reactor.lingers
    assert_equal 2, lingers[0]

    a.close
    assert_equal 1, lingers[0]

    b.close
    assert_equal 0, lingers.fetch(0, 0)
  ensure
    a&.close
    b&.close
  end
end
