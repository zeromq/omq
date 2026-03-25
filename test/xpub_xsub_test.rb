# frozen_string_literal: true

require_relative "test_helper"

describe "XPUB/XSUB" do
  before { OMQ::ZMTP::Transport::Inproc.reset! }

  it "XPUB receives subscription notifications" do
    Async do
      xpub = OMQ::XPUB.bind("inproc://xpub-sub-1")
      sub  = OMQ::SUB.new(nil, linger: 0, prefix: nil)
      sub.connect("inproc://xpub-sub-1")
      sub.subscribe("weather.")

      msg = xpub.receive
      assert_equal 1, msg.size
      assert_equal "\x01weather.".b, msg.first
    ensure
      sub&.close
      xpub&.close
    end
  end

  it "XPUB delivers messages to matching subscribers" do
    Async do
      xpub = OMQ::XPUB.bind("inproc://xpub-sub-2")
      sub  = OMQ::SUB.connect("inproc://xpub-sub-2", prefix: "news.")

      # Consume subscription notification
      xpub.receive

      xpub.send("news.headline")
      msg = sub.receive
      assert_equal ["news.headline"], msg
    ensure
      sub&.close
      xpub&.close
    end
  end

  it "XSUB sends subscriptions as data frames" do
    Async do
      pub  = OMQ::PUB.bind("inproc://pub-xsub-1")
      xsub = OMQ::XSUB.connect("inproc://pub-xsub-1")

      # Subscribe via XSUB data frame
      xsub.send("\x01stock.".b)

      # Wait for subscription to propagate
      Async::Task.current.yield

      pub.send("stock.AAPL")
      msg = xsub.receive
      assert_equal ["stock.AAPL"], msg
    ensure
      xsub&.close
      pub&.close
    end
  end

  it "XPUB receives unsubscription notifications" do
    Async do
      xpub = OMQ::XPUB.bind("inproc://xpub-unsub-1")
      sub  = OMQ::SUB.new(nil, linger: 0, prefix: nil)
      sub.connect("inproc://xpub-unsub-1")
      sub.subscribe("topic.")

      # Consume subscribe notification
      msg = xpub.receive
      assert_equal "\x01topic.".b, msg.first

      sub.unsubscribe("topic.")

      # Should receive unsubscribe notification
      msg = xpub.receive
      assert_equal 1, msg.size
      assert_equal "\x00topic.".b, msg.first
    ensure
      sub&.close
      xpub&.close
    end
  end
end
