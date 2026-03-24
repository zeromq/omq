# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"

describe OMQ::ZMTP::Codec::Frame do
  Frame = OMQ::ZMTP::Codec::Frame

  describe "#to_wire and .read_from round-trip" do
    it "handles empty body" do
      frame = Frame.new("".b)
      wire = frame.to_wire
      result = Frame.read_from(StringIO.new(wire))
      assert_equal "".b, result.body
      refute result.more?
      refute result.command?
    end

    it "handles short body (< 256 bytes)" do
      body = "hello world".b
      frame = Frame.new(body)
      wire = frame.to_wire
      # short frame: 1 byte flags + 1 byte size + body
      assert_equal 2 + body.bytesize, wire.bytesize
      result = Frame.read_from(StringIO.new(wire))
      assert_equal body, result.body
    end

    it "handles body at short frame boundary (255 bytes)" do
      body = ("x" * 255).b
      frame = Frame.new(body)
      wire = frame.to_wire
      assert_equal 2 + 255, wire.bytesize
      result = Frame.read_from(StringIO.new(wire))
      assert_equal body, result.body
    end

    it "handles long body (> 255 bytes)" do
      body = ("A" * 256).b
      frame = Frame.new(body)
      wire = frame.to_wire
      # long frame: 1 byte flags + 8 byte size + body
      assert_equal 9 + 256, wire.bytesize
      result = Frame.read_from(StringIO.new(wire))
      assert_equal body, result.body
    end

    it "preserves MORE flag" do
      frame = Frame.new("data".b, more: true)
      wire = frame.to_wire
      result = Frame.read_from(StringIO.new(wire))
      assert result.more?
      refute result.command?
    end

    it "preserves COMMAND flag" do
      frame = Frame.new("cmd".b, command: true)
      wire = frame.to_wire
      result = Frame.read_from(StringIO.new(wire))
      assert result.command?
      refute result.more?
    end

    it "preserves MORE + COMMAND flags together" do
      frame = Frame.new("data".b, more: true, command: true)
      wire = frame.to_wire
      result = Frame.read_from(StringIO.new(wire))
      assert result.more?
      assert result.command?
    end
  end

  describe "#to_wire encoding" do
    it "sets flags byte correctly for short frame" do
      frame = Frame.new("x".b, more: true)
      wire = frame.to_wire
      flags = wire.getbyte(0)
      assert_equal Frame::FLAGS_MORE, flags & Frame::FLAGS_MORE
      assert_equal 0, flags & Frame::FLAGS_LONG
    end

    it "sets LONG flag for large frames" do
      frame = Frame.new(("x" * 256).b)
      wire = frame.to_wire
      flags = wire.getbyte(0)
      assert_equal Frame::FLAGS_LONG, flags & Frame::FLAGS_LONG
    end

    it "encodes size as big-endian uint64 for long frames" do
      body = ("A" * 300).b
      frame = Frame.new(body)
      wire = frame.to_wire
      # bytes 1-8: big-endian uint64 size
      size_bytes = wire.byteslice(1, 8)
      size = size_bytes.unpack1("Q>")
      assert_equal 300, size
    end
  end

  describe ".read_from" do
    it "raises EOFError on empty IO" do
      assert_raises(EOFError) { Frame.read_from(StringIO.new("".b)) }
    end

    it "raises EOFError on truncated frame" do
      # flags byte says short frame, size says 10, but only 5 bytes of body
      wire = [0x00, 10].pack("CC") + ("x" * 5)
      assert_raises(EOFError) { Frame.read_from(StringIO.new(wire)) }
    end
  end
end
