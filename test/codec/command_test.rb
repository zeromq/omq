# frozen_string_literal: true

require_relative "../test_helper"

describe OMQ::ZMTP::Codec::Command do
  Command = OMQ::ZMTP::Codec::Command

  describe ".ready" do
    it "creates a READY command with socket type" do
      cmd = Command.ready(socket_type: "REQ")
      assert_equal "READY", cmd.name
    end

    it "encodes Socket-Type and Identity properties" do
      cmd = Command.ready(socket_type: "DEALER", identity: "my-id")
      props = cmd.properties
      assert_equal "DEALER", props["Socket-Type"]
      assert_equal "my-id", props["Identity"]
    end

    it "defaults identity to empty string" do
      cmd = Command.ready(socket_type: "PUB")
      props = cmd.properties
      assert_equal "", props["Identity"]
    end
  end

  describe ".subscribe / .cancel" do
    it "creates SUBSCRIBE command" do
      cmd = Command.subscribe("topic.")
      assert_equal "SUBSCRIBE", cmd.name
      assert_equal "topic.".b, cmd.data
    end

    it "creates CANCEL command" do
      cmd = Command.cancel("topic.")
      assert_equal "CANCEL", cmd.name
      assert_equal "topic.".b, cmd.data
    end

    it "handles empty prefix" do
      cmd = Command.subscribe("")
      assert_equal "SUBSCRIBE", cmd.name
      assert_equal "".b, cmd.data
    end
  end

  describe "#to_body / .from_body round-trip" do
    it "round-trips a READY command" do
      original = Command.ready(socket_type: "ROUTER", identity: "test-123")
      body = original.to_body
      decoded = Command.from_body(body)
      assert_equal "READY", decoded.name
      props = decoded.properties
      assert_equal "ROUTER", props["Socket-Type"]
      assert_equal "test-123", props["Identity"]
    end

    it "round-trips a SUBSCRIBE command" do
      original = Command.subscribe("weather.")
      body = original.to_body
      decoded = Command.from_body(body)
      assert_equal "SUBSCRIBE", decoded.name
      assert_equal "weather.".b, decoded.data
    end
  end

  describe "#to_frame" do
    it "produces a Frame with command flag set" do
      cmd = Command.ready(socket_type: "REQ")
      frame = cmd.to_frame
      assert frame.command?
      refute frame.more?
    end
  end

  describe ".from_body" do
    it "raises on empty body" do
      assert_raises(OMQ::ZMTP::ProtocolError) { Command.from_body("".b) }
    end

    it "raises on truncated name" do
      # name_len says 10 but only 3 bytes follow
      assert_raises(OMQ::ZMTP::ProtocolError) { Command.from_body("\x0Aabc".b) }
    end
  end

  describe "#properties" do
    it "parses multiple properties" do
      cmd = Command.ready(socket_type: "SUB", identity: "id-42")
      props = cmd.properties
      assert_equal 2, props.size
      assert_equal "SUB", props["Socket-Type"]
      assert_equal "id-42", props["Identity"]
    end

    it "raises on truncated property name" do
      # Valid name-len but truncated data
      bad_data = "\x05AB".b # name_len=5 but only 2 bytes
      cmd = Command.new("READY", bad_data)
      assert_raises(OMQ::ZMTP::ProtocolError) { cmd.properties }
    end

    it "raises on truncated property value length" do
      # Valid name but truncated value length field
      bad_data = "\x01X\x00".b # name_len=1, name="X", only 1 byte of value_len
      cmd = Command.new("READY", bad_data)
      assert_raises(OMQ::ZMTP::ProtocolError) { cmd.properties }
    end
  end
end
