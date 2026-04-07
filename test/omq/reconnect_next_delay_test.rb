# frozen_string_literal: true

require_relative "../test_helper"

describe "Reconnect#next_delay" do
  def build_reconnect(reconnect_interval)
    options = OMQ::Options.new
    options.reconnect_interval = reconnect_interval
    OMQ::Engine::Reconnect.send(:new, nil, "tcp://127.0.0.1:5555", options)
  end


  describe "plain Numeric (fixed interval, no backoff)" do
    it "returns the same interval every time" do
      r = build_reconnect(0.1)
      _delay, max = r.send(:init_delay, nil)
      assert_equal 0.1, _delay
      assert_nil max

      10.times do
        _delay = r.send(:next_delay, _delay, max)
        assert_equal 0.1, _delay
      end
    end
  end


  describe "Range (exponential backoff)" do
    it "doubles delay up to the max" do
      r = build_reconnect(0.1..2.0)
      delay, max = r.send(:init_delay, nil)
      assert_equal 0.1, delay
      assert_equal 2.0, max

      delay = r.send(:next_delay, delay, max)
      assert_equal 0.2, delay

      delay = r.send(:next_delay, delay, max)
      assert_equal 0.4, delay

      delay = r.send(:next_delay, delay, max)
      assert_equal 0.8, delay

      delay = r.send(:next_delay, delay, max)
      assert_equal 1.6, delay

      # Capped at max
      delay = r.send(:next_delay, delay, max)
      assert_equal 2.0, delay

      delay = r.send(:next_delay, delay, max)
      assert_equal 2.0, delay
    end


    it "recovers from zero initial delay (immediate first attempt)" do
      r = build_reconnect(0.05..1.0)
      delay = r.send(:next_delay, 0, 1.0)
      assert_equal 0.05, delay
    end
  end
end
