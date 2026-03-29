# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/omq/cli"
require "json"
require "stringio"

HAS_MSGPACK = begin; require "msgpack"; true; rescue LoadError; false; end
HAS_ZSTD    = begin; require "zstd-ruby"; true; rescue LoadError; false; end

# Suppress stderr/stdout from abort/puts during validation tests.
def quietly
  orig_stderr = $stderr
  orig_stdout = $stdout
  $stderr = StringIO.new
  $stdout = StringIO.new
  yield
ensure
  $stderr = orig_stderr
  $stdout = orig_stdout
end

# ── Formatter ────────────────────────────────────────────────────────

describe OMQ::CLI::Formatter do

  # ── ASCII format ─────────────────────────────────────────────────

  describe "ascii" do
    before { @fmt = OMQ::CLI::Formatter.new(:ascii) }

    it "encodes single-frame message" do
      assert_equal "hello\n", @fmt.encode(["hello"])
    end

    it "encodes multipart as tab-separated" do
      assert_equal "frame1\tframe2\tframe3\n", @fmt.encode(["frame1", "frame2", "frame3"])
    end

    it "replaces non-printable bytes with dots" do
      assert_equal "hel.o\n", @fmt.encode(["hel\x00o"])
      assert_equal "ab..cd\n", @fmt.encode(["ab\x01\x02cd"])
    end

    it "preserves tabs in output" do
      assert_equal "a\tb\n", @fmt.encode(["a\tb"])
    end

    it "encodes empty message" do
      assert_equal "\n", @fmt.encode([""])
    end

    it "decodes single-frame message" do
      assert_equal ["hello"], @fmt.decode("hello\n")
    end

    it "decodes tab-separated into multipart" do
      assert_equal ["frame1", "frame2"], @fmt.decode("frame1\tframe2\n")
    end

    it "decodes empty line as empty array" do
      assert_equal [], @fmt.decode("\n")
    end

    it "round-trips printable text" do
      parts = ["hello", "world"]
      assert_equal parts, @fmt.decode(@fmt.encode(parts))
    end
  end

  # ── Quoted format ────────────────────────────────────────────────

  describe "quoted" do
    before { @fmt = OMQ::CLI::Formatter.new(:quoted) }

    it "encodes printable text unchanged" do
      assert_equal "hello world\n", @fmt.encode(["hello world"])
    end

    it "escapes newlines" do
      assert_equal "line1\\nline2\n", @fmt.encode(["line1\nline2"])
    end

    it "escapes carriage returns" do
      assert_equal "a\\rb\n", @fmt.encode(["a\rb"])
    end

    it "escapes tabs" do
      assert_equal "a\\tb\n", @fmt.encode(["a\tb"])
    end

    it "escapes backslashes" do
      assert_equal "a\\\\b\n", @fmt.encode(["a\\b"])
    end

    it "hex-escapes other non-printable bytes" do
      assert_equal "\\x00\\x01\\x7F\n", @fmt.encode(["\x00\x01\x7f"])
    end

    it "encodes multipart as tab-separated" do
      assert_equal "part1\tpart2\n", @fmt.encode(["part1", "part2"])
    end

    it "decodes escaped newlines" do
      assert_equal ["line1\nline2"], @fmt.decode("line1\\nline2\n")
    end

    it "decodes escaped carriage returns" do
      assert_equal ["a\rb"], @fmt.decode("a\\rb\n")
    end

    it "decodes escaped tabs" do
      assert_equal ["a\tb"], @fmt.decode("a\\tb\n")
    end

    it "decodes escaped backslashes" do
      assert_equal ["a\\b"], @fmt.decode("a\\\\b\n")
    end

    it "decodes hex escapes" do
      assert_equal ["\x00\xff".b], @fmt.decode("\\x00\\xFF\n").map(&:b)
    end

    it "round-trips text with special characters" do
      parts = ["line1\nline2\ttab\\back"]
      assert_equal parts, @fmt.decode(@fmt.encode(parts))
    end

    it "round-trips binary data" do
      binary = (0..255).map(&:chr).join.b
      encoded = @fmt.encode([binary])
      decoded = @fmt.decode(encoded).first.b
      assert_equal binary, decoded
    end
  end

  # ── Raw format ───────────────────────────────────────────────────

  describe "raw" do
    before { @fmt = OMQ::CLI::Formatter.new(:raw) }

    it "encodes by joining parts" do
      assert_equal "helloworld", @fmt.encode(["hello", "world"])
    end

    it "encodes empty message" do
      assert_equal "", @fmt.encode([""])
    end

    it "decodes line as single-element array" do
      assert_equal ["hello\n"], @fmt.decode("hello\n")
    end

    it "preserves binary data" do
      binary = "\x00\x01\xff".b
      assert_equal [binary], @fmt.decode(binary)
    end
  end

  # ── JSONL format ─────────────────────────────────────────────────

  describe "jsonl" do
    before { @fmt = OMQ::CLI::Formatter.new(:jsonl) }

    it "encodes as JSON array" do
      assert_equal "[\"hello\"]\n", @fmt.encode(["hello"])
    end

    it "encodes multipart as JSON array" do
      assert_equal "[\"a\",\"b\",\"c\"]\n", @fmt.encode(["a", "b", "c"])
    end

    it "encodes empty parts" do
      assert_equal "[\"\"]\n", @fmt.encode([""])
    end

    it "decodes JSON array" do
      assert_equal ["hello"], @fmt.decode("[\"hello\"]\n")
    end

    it "decodes multipart JSON array" do
      assert_equal ["a", "b"], @fmt.decode("[\"a\",\"b\"]\n")
    end

    it "round-trips multipart messages" do
      parts = ["frame1", "frame2", "frame3"]
      assert_equal parts, @fmt.decode(@fmt.encode(parts))
    end

    it "handles special JSON characters" do
      parts = ["line\nnew", "tab\there", "quote\"end"]
      assert_equal parts, @fmt.decode(@fmt.encode(parts))
    end
  end

  # ── MessagePack format ──────────────────────────────────────────

  if HAS_MSGPACK
    describe "msgpack" do
      before { @fmt = OMQ::CLI::Formatter.new(:msgpack) }

      it "encodes as MessagePack" do
        encoded = @fmt.encode(["hello"])
        assert_equal ["hello"], MessagePack.unpack(encoded)
      end

      it "encodes multipart" do
        encoded = @fmt.encode(["a", "b", "c"])
        assert_equal ["a", "b", "c"], MessagePack.unpack(encoded)
      end

      it "decodes from IO stream" do
        data   = MessagePack.pack(["hello", "world"])
        io     = StringIO.new(data)
        result = @fmt.decode_msgpack(io)
        assert_equal ["hello", "world"], result
      end

      it "decodes multiple messages from stream" do
        data = MessagePack.pack(["msg1"]) + MessagePack.pack(["msg2"])
        io   = StringIO.new(data)
        assert_equal ["msg1"], @fmt.decode_msgpack(io)
        assert_equal ["msg2"], @fmt.decode_msgpack(io)
      end

      it "returns nil at EOF" do
        io = StringIO.new("")
        assert_nil @fmt.decode_msgpack(io)
      end
    end
  end

  # ── Compression ─────────────────────────────────────────────────

  describe "compression" do
    it "passes through when disabled" do
      fmt   = OMQ::CLI::Formatter.new(:ascii)
      parts = ["hello", "world"]
      assert_same parts, fmt.compress(parts)
      assert_same parts, fmt.decompress(parts)
    end

    if HAS_ZSTD
      it "round-trips with compression enabled" do
        fmt        = OMQ::CLI::Formatter.new(:ascii, compress: true)
        parts      = ["hello", "world"]
        compressed = fmt.compress(parts)
        refute_equal parts, compressed
        assert_equal parts, fmt.decompress(compressed)
      end

      it "compresses large data" do
        fmt   = OMQ::CLI::Formatter.new(:ascii, compress: true)
        big   = ["x" * 10_000]
        small = fmt.compress(big)
        assert_operator small.first.bytesize, :<, big.first.bytesize
        assert_equal big, fmt.decompress(small)
      end
    end
  end
end

# ── Routing helpers ──────────────────────────────────────────────────

describe "Routing helpers" do
  before do
    @runner = OMQ::CLI::Runner.new(
      { type_name: "server", connects: [], binds: [] },
      OMQ::SERVER
    )
  end

  describe "#display_routing_id" do
    it "passes through printable ASCII" do
      assert_equal "worker-1", @runner.send(:display_routing_id, "worker-1")
    end

    it "hex-encodes binary IDs" do
      assert_equal "0xdeadbeef", @runner.send(:display_routing_id, "\xDE\xAD\xBE\xEF".b)
    end

    it "hex-encodes IDs with leading zero" do
      assert_equal "0x00abcdef42", @runner.send(:display_routing_id, "\x00\xAB\xCD\xEF\x42".b)
    end

    it "hex-encodes IDs containing a mix of printable and non-printable" do
      id = "ab\x00cd".b
      displayed = @runner.send(:display_routing_id, id)
      assert displayed.start_with?("0x"), "expected hex encoding for mixed ID"
    end

    it "handles empty string" do
      assert_equal "", @runner.send(:display_routing_id, "")
    end
  end

  describe "#resolve_target" do
    it "decodes 0x-prefixed hex" do
      assert_equal "\xDE\xAD\xBE\xEF".b, @runner.send(:resolve_target, "0xdeadbeef")
    end

    it "decodes uppercase hex" do
      assert_equal "\xDE\xAD".b, @runner.send(:resolve_target, "0xDEAD")
    end

    it "strips spaces in hex" do
      assert_equal "\xDE\xAD\xBE\xEF".b, @runner.send(:resolve_target, "0xde ad be ef")
    end

    it "passes through plain text" do
      assert_equal "worker-1", @runner.send(:resolve_target, "worker-1")
    end

    it "passes through text that looks like hex but has no 0x prefix" do
      assert_equal "deadbeef", @runner.send(:resolve_target, "deadbeef")
    end
  end

  describe "round-trip" do
    it "round-trips 4-byte binary routing ID" do
      original  = "\xBF\x5D\x07\x01".b
      displayed = @runner.send(:display_routing_id, original)
      resolved  = @runner.send(:resolve_target, displayed)
      assert_equal original, resolved
    end

    it "round-trips 5-byte binary routing ID" do
      original  = "\x00\xAB\xCD\xEF\x42".b
      displayed = @runner.send(:display_routing_id, original)
      resolved  = @runner.send(:resolve_target, displayed)
      assert_equal original, resolved
    end

    it "round-trips ASCII identity" do
      original  = "my-worker"
      displayed = @runner.send(:display_routing_id, original)
      resolved  = @runner.send(:resolve_target, displayed)
      assert_equal original, resolved
    end
  end
end

# ── Validation ───────────────────────────────────────────────────────

describe "OMQ::CLI.validate!" do
  def base_opts(type_name)
    {
      type_name:  type_name,
      connects:   ["tcp://localhost:5555"],
      binds:      [],
      data:       nil,
      file:       nil,
      subscribes: [],
      joins:      [],
      group:      nil,
      identity:   nil,
      target:     nil,
    }
  end

  it "passes with valid options" do
    OMQ::CLI.validate!(base_opts("req"))
  end

  it "rejects missing connect and bind" do
    opts = base_opts("req").merge(connects: [], binds: [])
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "rejects --data and --file together" do
    opts = base_opts("req").merge(data: "hello", file: "test.txt")
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "rejects --subscribe on non-SUB" do
    opts = base_opts("pull").merge(subscribes: ["topic"])
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "allows --subscribe on SUB" do
    OMQ::CLI.validate!(base_opts("sub").merge(subscribes: ["topic"]))
  end

  it "rejects --join on non-DISH" do
    opts = base_opts("pull").merge(joins: ["group1"])
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "allows --join on DISH" do
    OMQ::CLI.validate!(base_opts("dish").merge(joins: ["group1"]))
  end

  it "rejects --group on non-RADIO" do
    opts = base_opts("pub").merge(group: "weather")
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "allows --group on RADIO" do
    OMQ::CLI.validate!(base_opts("radio").merge(group: "weather"))
  end

  it "rejects --identity on non-DEALER/ROUTER" do
    opts = base_opts("req").merge(identity: "my-id")
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "allows --identity on DEALER" do
    OMQ::CLI.validate!(base_opts("dealer").merge(identity: "my-id"))
  end

  it "allows --identity on ROUTER" do
    OMQ::CLI.validate!(base_opts("router").merge(identity: "my-id"))
  end

  it "rejects --target on non-ROUTER/SERVER/PEER" do
    opts = base_opts("dealer").merge(target: "peer-1")
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "allows --target on ROUTER" do
    OMQ::CLI.validate!(base_opts("router").merge(target: "peer-1"))
  end

  it "allows --target on SERVER" do
    OMQ::CLI.validate!(base_opts("server").merge(target: "0xdeadbeef"))
  end

  it "allows --target on PEER" do
    OMQ::CLI.validate!(base_opts("peer").merge(target: "0xdeadbeef"))
  end

  it "rejects inproc URLs" do
    opts = base_opts("req").merge(connects: ["inproc://test"])
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end
end

# ── Option parsing ───────────────────────────────────────────────────

describe "OMQ::CLI.parse_options" do
  it "parses socket type" do
    opts = OMQ::CLI.parse_options(["req", "-c", "tcp://localhost:5555"])
    assert_equal "req", opts[:type_name]
  end

  it "parses socket type case-insensitively" do
    opts = OMQ::CLI.parse_options(["REQ", "-c", "tcp://localhost:5555"])
    assert_equal "req", opts[:type_name]
  end

  it "collects multiple connects" do
    opts = OMQ::CLI.parse_options(["push", "-c", "tcp://a:1", "-c", "tcp://b:2"])
    assert_equal ["tcp://a:1", "tcp://b:2"], opts[:connects]
  end

  it "collects multiple binds" do
    opts = OMQ::CLI.parse_options(["pull", "-b", "tcp://:1", "-b", "tcp://:2"])
    assert_equal ["tcp://:1", "tcp://:2"], opts[:binds]
  end

  it "parses format flags" do
    assert_equal :quoted, OMQ::CLI.parse_options(["req", "-c", "tcp://x:1", "-Q"])[:format]
    assert_equal :raw,    OMQ::CLI.parse_options(["req", "-c", "tcp://x:1", "--raw"])[:format]
    assert_equal :jsonl,  OMQ::CLI.parse_options(["req", "-c", "tcp://x:1", "-J"])[:format]
  end

  it "parses draft type names" do
    %w[client server radio dish scatter gather channel peer].each do |type|
      opts = OMQ::CLI.parse_options([type, "-c", "tcp://x:1"])
      assert_equal type, opts[:type_name]
    end
  end

  it "parses --join and --group" do
    opts = OMQ::CLI.parse_options(["dish", "-b", "tcp://:1", "-j", "g1", "-j", "g2"])
    assert_equal ["g1", "g2"], opts[:joins]

    opts = OMQ::CLI.parse_options(["radio", "-c", "tcp://x:1", "-g", "weather"])
    assert_equal "weather", opts[:group]
  end

  it "exits on unknown socket type" do
    assert_raises(SystemExit) { quietly { OMQ::CLI.parse_options(["bogus", "-c", "tcp://x:1"]) } }
  end

  it "exits with no arguments" do
    assert_raises(SystemExit) { quietly { OMQ::CLI.parse_options([]) } }
  end
end

# ── Eval ($F and $_) ────────────────────────────────────────────────

describe "eval_expr" do
  before do
    @runner = OMQ::CLI::Runner.new(
      { type_name: "push", connects: [], binds: [], expr: "[$_, *$F]" },
      OMQ::PUSH
    )
    @runner.send(:compile_expr)
  end

  it "sets $F to message parts" do
    result = @runner.send(:eval_expr, ["hello", "world"])
    assert_equal ["hello", "hello", "world"], result
  end

  it "sets $_ to first frame" do
    result = @runner.send(:eval_expr, ["first", "second"])
    assert_equal "first", result.first
  end

  it "sets $_ to nil when parts is nil" do
    runner = OMQ::CLI::Runner.new(
      { type_name: "push", connects: [], binds: [], expr: "$_.nil? ? 'yes' : 'no'" },
      OMQ::PUSH
    )
    runner.send(:compile_expr)
    result = runner.send(:eval_expr, nil)
    assert_equal ["yes"], result
  end

  it "returns nil when expression evaluates to nil" do
    runner = OMQ::CLI::Runner.new(
      { type_name: "push", connects: [], binds: [], expr: "nil" },
      OMQ::PUSH
    )
    runner.send(:compile_expr)
    assert_nil runner.send(:eval_expr, ["anything"])
  end

  it "wraps string result in array" do
    runner = OMQ::CLI::Runner.new(
      { type_name: "push", connects: [], binds: [], expr: "'hello'" },
      OMQ::PUSH
    )
    runner.send(:compile_expr)
    assert_equal ["hello"], runner.send(:eval_expr, nil)
  end
end

# ── Output ──────────────────────────────────────────────────────────

describe "output" do
  before do
    @runner = OMQ::CLI::Runner.new(
      { type_name: "pull", connects: [], binds: [], quiet: false, format: :ascii },
      OMQ::PULL
    )
  end

  it "skips nil parts" do
    out = StringIO.new
    $stdout = out
    @runner.send(:output, nil)
    $stdout = STDOUT
    assert_equal "", out.string
  end

  it "prints message parts" do
    out = StringIO.new
    $stdout = out
    @runner.send(:output, ["hello"])
    $stdout = STDOUT
    assert_equal "hello\n", out.string
  end
end
