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

# Helper to build a minimal Config for unit tests.
def make_config(type_name:, **overrides)
  defaults = {
    type_name:       type_name,
    endpoints:       [],
    connects:        [],
    binds:           [],
    in_endpoints:    [],
    out_endpoints:   [],
    data:            nil,
    file:            nil,
    format:          :ascii,
    subscribes:      [],
    joins:           [],
    group:           nil,
    identity:        nil,
    target:          nil,
    interval:        nil,
    count:           nil,
    delay:           nil,
    timeout:         nil,
    linger:          5,
    reconnect_ivl:   nil,
    heartbeat_ivl:   nil,
    conflate:        false,
    compress:        false,
    send_expr:       nil,
    recv_expr:       nil,
    parallel:        nil,
    transient:       false,
    verbose:         false,
    quiet:           false,
    echo:            false,
    curve_server:    false,
    curve_server_key: nil,
    has_msgpack:     false,
    has_zstd:        false,
    stdin_is_tty:    true,
  }
  OMQ::CLI::Config.new(**defaults.merge(overrides))
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

    it "encodes as ZMTP frames" do
      encoded = @fmt.encode(["hello", "world"])
      assert_equal "\x01\x05hello\x00\x05world".b, encoded
    end

    it "encodes empty message" do
      assert_equal "\x00\x00".b, @fmt.encode([""])
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
    @runner = OMQ::CLI::ServerRunner.new(
      make_config(type_name: "server"),
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
      type_name:      type_name,
      endpoints:      [OMQ::CLI::Endpoint.new("tcp://localhost:5555", false)],
      connects:       ["tcp://localhost:5555"],
      binds:          [],
      in_endpoints:   [],
      out_endpoints:  [],
      data:           nil,
      file:           nil,
      subscribes:     [],
      joins:          [],
      group:          nil,
      identity:       nil,
      target:         nil,
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

  # ── --recv-eval / --send-eval validation ──────────────────────────

  it "rejects --recv-eval on send-only sockets" do
    %w[push pub scatter radio].each do |type|
      opts = base_opts(type).merge(recv_expr: "$F")
      assert_raises(SystemExit, "expected --recv-eval to be rejected for #{type}") {
        quietly { OMQ::CLI.validate!(opts) }
      }
    end
  end

  it "rejects --send-eval on recv-only sockets" do
    %w[pull sub gather dish].each do |type|
      opts = base_opts(type).merge(send_expr: "$F")
      assert_raises(SystemExit, "expected --send-eval to be rejected for #{type}") {
        quietly { OMQ::CLI.validate!(opts) }
      }
    end
  end

  it "rejects --send-eval combined with --target" do
    %w[router server peer].each do |type|
      opts = base_opts(type).merge(send_expr: "$F", target: "peer-1")
      assert_raises(SystemExit, "expected --send-eval + --target to be rejected for #{type}") {
        quietly { OMQ::CLI.validate!(opts) }
      }
    end
  end

  it "allows --recv-eval on recv-only sockets" do
    %w[pull sub gather dish].each do |type|
      OMQ::CLI.validate!(base_opts(type).merge(recv_expr: "$F"))
    end
  end

  it "allows --send-eval on send-only sockets" do
    %w[push pub scatter radio].each do |type|
      OMQ::CLI.validate!(base_opts(type).merge(send_expr: "$F"))
    end
  end

  it "allows --send-eval on ROUTER without --target" do
    OMQ::CLI.validate!(base_opts("router").merge(send_expr: '["id", $_]'))
  end

  it "allows both --send-eval and --recv-eval on bidirectional sockets" do
    %w[req rep pair dealer router client server peer channel].each do |type|
      next if %w[rep].include?(type) # REP send-eval may not apply but validation doesn't block it
      OMQ::CLI.validate!(base_opts(type).merge(send_expr: "$F", recv_expr: "$F"))
    end
  end

  # ── pipe --in/--out validation ──────────────────────────────────

  def pipe_opts(**overrides)
    {
      type_name:      "pipe",
      endpoints:      [],
      connects:       [],
      binds:          [],
      in_endpoints:   [],
      out_endpoints:  [],
      data:           nil,
      file:           nil,
      subscribes:     [],
      joins:          [],
      group:          nil,
      identity:       nil,
      target:         nil,
    }.merge(overrides)
  end

  it "allows pipe with --in/--out endpoints" do
    opts = pipe_opts(
      in_endpoints:  [OMQ::CLI::Endpoint.new("ipc://@a", false)],
      out_endpoints: [OMQ::CLI::Endpoint.new("ipc://@b", false)],
    )
    OMQ::CLI.validate!(opts)
  end

  it "allows pipe with multiple --in endpoints" do
    opts = pipe_opts(
      in_endpoints:  [OMQ::CLI::Endpoint.new("ipc://@a", false), OMQ::CLI::Endpoint.new("ipc://@b", false)],
      out_endpoints: [OMQ::CLI::Endpoint.new("ipc://@c", false)],
    )
    OMQ::CLI.validate!(opts)
  end

  it "rejects pipe --in without --out" do
    opts = pipe_opts(in_endpoints: [OMQ::CLI::Endpoint.new("ipc://@a", false)])
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "rejects pipe --out without --in" do
    opts = pipe_opts(out_endpoints: [OMQ::CLI::Endpoint.new("ipc://@a", false)])
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "rejects pipe mixing --in/--out with bare endpoints" do
    opts = pipe_opts(
      in_endpoints: [OMQ::CLI::Endpoint.new("ipc://@a", false)],
      out_endpoints: [OMQ::CLI::Endpoint.new("ipc://@b", false)],
      endpoints: [OMQ::CLI::Endpoint.new("ipc://@c", false)],
    )
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "rejects --in/--out on non-pipe sockets" do
    opts = base_opts("req").merge(in_endpoints: [OMQ::CLI::Endpoint.new("ipc://@a", false)], out_endpoints: [])
    assert_raises(SystemExit) { quietly { OMQ::CLI.validate!(opts) } }
  end

  it "allows legacy pipe with exactly 2 positional endpoints" do
    eps = [OMQ::CLI::Endpoint.new("ipc://@a", false), OMQ::CLI::Endpoint.new("ipc://@b", false)]
    opts = pipe_opts(endpoints: eps)
    OMQ::CLI.validate!(opts)
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
    assert_equal ["tcp://localhost:1", "tcp://localhost:2"], opts[:binds]
  end

  it "expands tcp://*:PORT to 0.0.0.0" do
    opts = OMQ::CLI.parse_options(["pull", "-b", "tcp://*:1234"])
    assert_equal ["tcp://0.0.0.0:1234"], opts[:binds]
  end

  it "expands tcp://:PORT to localhost for connects" do
    opts = OMQ::CLI.parse_options(["push", "-c", "tcp://:1234"])
    assert_equal ["tcp://localhost:1234"], opts[:connects]
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

  it "parses --reconnect-ivl as a fixed value" do
    opts = OMQ::CLI.parse_options(["req", "-c", "tcp://x:1", "--reconnect-ivl", "0.5"])
    assert_equal 0.5, opts[:reconnect_ivl]
  end

  it "parses --reconnect-ivl as a range" do
    opts = OMQ::CLI.parse_options(["req", "-c", "tcp://x:1", "--reconnect-ivl", "0.1..2"])
    assert_equal 0.1..2.0, opts[:reconnect_ivl]
  end

  it "parses -e as --recv-eval" do
    opts = OMQ::CLI.parse_options(["pull", "-b", "tcp://:1", "-e", "$F.map(&:upcase)"])
    assert_equal "$F.map(&:upcase)", opts[:recv_expr]
    assert_nil opts[:send_expr]
  end

  it "parses -E as --send-eval" do
    opts = OMQ::CLI.parse_options(["push", "-c", "tcp://x:1", "-E", "$F.map(&:upcase)"])
    assert_equal "$F.map(&:upcase)", opts[:send_expr]
    assert_nil opts[:recv_expr]
  end

  it "parses --recv-eval long form" do
    opts = OMQ::CLI.parse_options(["pull", "-b", "tcp://:1", "--recv-eval", "$_"])
    assert_equal "$_", opts[:recv_expr]
  end

  it "parses --send-eval long form" do
    opts = OMQ::CLI.parse_options(["push", "-c", "tcp://x:1", "--send-eval", "$_"])
    assert_equal "$_", opts[:send_expr]
  end

  it "parses both -e and -E together" do
    opts = OMQ::CLI.parse_options(["req", "-c", "tcp://x:1", "-E", "build($_)", "-e", "parse($_)"])
    assert_equal "build($_)",  opts[:send_expr]
    assert_equal "parse($_)", opts[:recv_expr]
  end

  it "parses --in/--out modal endpoints for pipe" do
    opts = OMQ::CLI.parse_options(["pipe", "--in", "-c", "ipc://@a", "-c", "ipc://@b", "--out", "-c", "ipc://@c"])
    assert_equal 2, opts[:in_endpoints].size
    assert_equal 1, opts[:out_endpoints].size
    assert_equal "ipc://@a", opts[:in_endpoints][0].url
    assert_equal "ipc://@b", opts[:in_endpoints][1].url
    assert_equal "ipc://@c", opts[:out_endpoints][0].url
    assert_empty opts[:endpoints]
  end

  it "parses --in with bind and --out with connect" do
    opts = OMQ::CLI.parse_options(["pipe", "--in", "-b", "tcp://:5555", "--out", "-c", "tcp://x:5556"])
    assert opts[:in_endpoints][0].bind?
    refute opts[:out_endpoints][0].bind?
  end

  it "parses legacy pipe with bare -c (no --in/--out)" do
    opts = OMQ::CLI.parse_options(["pipe", "-c", "ipc://@a", "-c", "ipc://@b"])
    assert_equal 2, opts[:endpoints].size
    assert_empty opts[:in_endpoints]
    assert_empty opts[:out_endpoints]
  end
end

# ── Eval ($F and $_) ────────────────────────────────────────────────

describe "eval_send_expr" do
  before do
    @runner = OMQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "[$_, *$F]"),
      OMQ::PUSH
    )
    @runner.send(:compile_expr)
  end

  it "sets $F to message parts" do
    result = @runner.send(:eval_send_expr, ["hello", "world"])
    assert_equal ["hello", "hello", "world"], result
  end

  it "sets $_ to first frame" do
    result = @runner.send(:eval_send_expr, ["first", "second"])
    assert_equal "first", result.first
  end

  it "sets $_ to nil when parts is nil" do
    runner = OMQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "$_.nil? ? 'yes' : 'no'"),
      OMQ::PUSH
    )
    runner.send(:compile_expr)
    result = runner.send(:eval_send_expr, nil)
    assert_equal ["yes"], result
  end

  it "returns nil when expression evaluates to nil" do
    runner = OMQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "nil"),
      OMQ::PUSH
    )
    runner.send(:compile_expr)
    assert_nil runner.send(:eval_send_expr, ["anything"])
  end

  it "returns SENT when expression returns the socket (self <<)" do
    Async do
      OMQ::ZMTP::Transport::Inproc.reset!
      push = OMQ::PUSH.bind("inproc://eval-self-send")
      pull = OMQ::PULL.connect("inproc://eval-self-send")
      runner = OMQ::CLI::PushRunner.new(
        make_config(type_name: "push", send_expr: "self << $F"),
        OMQ::PUSH
      )
      runner.send(:compile_expr)
      runner.instance_variable_set(:@sock, push)
      result = runner.send(:eval_send_expr, ["hello"])
      assert_equal OMQ::CLI::BaseRunner::SENT, result
    ensure
      push&.close
      pull&.close
    end
  end

  it "wraps string result in array" do
    runner = OMQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "'hello'"),
      OMQ::PUSH
    )
    runner.send(:compile_expr)
    assert_equal ["hello"], runner.send(:eval_send_expr, nil)
  end
end

describe "eval_recv_expr" do
  it "transforms incoming messages" do
    runner = OMQ::CLI::PullRunner.new(
      make_config(type_name: "pull", recv_expr: "$F.map(&:upcase)"),
      OMQ::PULL
    )
    runner.send(:compile_expr)
    result = runner.send(:eval_recv_expr, ["hello", "world"])
    assert_equal ["HELLO", "WORLD"], result
  end

  it "returns parts unchanged when no recv_expr" do
    runner = OMQ::CLI::PullRunner.new(
      make_config(type_name: "pull"),
      OMQ::PULL
    )
    runner.send(:compile_expr)
    result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["hello"], result
  end

  it "returns nil when expression evaluates to nil (filtering)" do
    runner = OMQ::CLI::PullRunner.new(
      make_config(type_name: "pull", recv_expr: "nil"),
      OMQ::PULL
    )
    runner.send(:compile_expr)
    assert_nil runner.send(:eval_recv_expr, ["anything"])
  end

  it "sets $_ to first frame" do
    runner = OMQ::CLI::PullRunner.new(
      make_config(type_name: "pull", recv_expr: "$_"),
      OMQ::PULL
    )
    runner.send(:compile_expr)
    result = runner.send(:eval_recv_expr, ["first", "second"])
    assert_equal ["first"], result
  end
end


describe "independent send and recv eval" do
  it "compiles send and recv procs independently" do
    runner = OMQ::CLI::ReqRunner.new(
      make_config(type_name: "req", send_expr: "$F.map(&:upcase)", recv_expr: "$F.map(&:reverse)"),
      OMQ::REQ
    )
    runner.send(:compile_expr)

    send_result = runner.send(:eval_send_expr, ["hello"])
    assert_equal ["HELLO"], send_result

    recv_result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["olleh"], recv_result
  end

  it "allows send_expr without recv_expr" do
    runner = OMQ::CLI::ReqRunner.new(
      make_config(type_name: "req", send_expr: "$F.map(&:upcase)"),
      OMQ::REQ
    )
    runner.send(:compile_expr)

    send_result = runner.send(:eval_send_expr, ["hello"])
    assert_equal ["HELLO"], send_result

    recv_result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["hello"], recv_result
  end

  it "allows recv_expr without send_expr" do
    runner = OMQ::CLI::ReqRunner.new(
      make_config(type_name: "req", recv_expr: "$F.map(&:upcase)"),
      OMQ::REQ
    )
    runner.send(:compile_expr)

    send_result = runner.send(:eval_send_expr, ["hello"])
    assert_equal ["hello"], send_result

    recv_result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["HELLO"], recv_result
  end
end


describe "BEGIN/END blocks per direction" do
  it "compiles BEGIN/END for send_expr" do
    runner = OMQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: 'BEGIN{ @count = 0 } @count += 1; $F END{ }'),
      OMQ::PUSH
    )
    runner.send(:compile_expr)
    refute_nil runner.instance_variable_get(:@send_begin_proc)
    assert_nil runner.instance_variable_get(:@recv_begin_proc)
  end

  it "compiles BEGIN/END for recv_expr" do
    runner = OMQ::CLI::PullRunner.new(
      make_config(type_name: "pull", recv_expr: 'BEGIN{ @sum = 0 } @sum += Integer($_); next END{ puts @sum }'),
      OMQ::PULL
    )
    runner.send(:compile_expr)
    refute_nil runner.instance_variable_get(:@recv_begin_proc)
    assert_nil runner.instance_variable_get(:@send_begin_proc)
  end

  it "compiles BEGIN/END independently for both directions" do
    runner = OMQ::CLI::PairRunner.new(
      make_config(type_name: "pair",
                  send_expr: 'BEGIN{ @send_count = 0 } @send_count += 1; $F',
                  recv_expr: 'BEGIN{ @recv_count = 0 } @recv_count += 1; $F'),
      OMQ::PAIR
    )
    runner.send(:compile_expr)
    refute_nil runner.instance_variable_get(:@send_begin_proc)
    refute_nil runner.instance_variable_get(:@recv_begin_proc)
  end
end

# ── Registration API (OMQ.outgoing / OMQ.incoming) ──────────────

describe "OMQ.outgoing / OMQ.incoming registration" do
  after do
    # Clean up registered procs between tests
    OMQ.instance_variable_set(:@outgoing_proc, nil)
    OMQ.instance_variable_set(:@incoming_proc, nil)
  end

  it "registers an outgoing proc" do
    OMQ.outgoing { $F.map(&:upcase) }
    refute_nil OMQ.outgoing_proc
  end

  it "registers an incoming proc" do
    OMQ.incoming { $F.map(&:downcase) }
    refute_nil OMQ.incoming_proc
  end

  it "picks up registered procs during compile_expr" do
    OMQ.outgoing { $F.map(&:upcase) }
    OMQ.incoming { $F.map(&:reverse) }

    runner = OMQ::CLI::ReqRunner.new(
      make_config(type_name: "req"),
      OMQ::REQ
    )
    runner.send(:compile_expr)

    refute_nil runner.instance_variable_get(:@send_eval_proc)
    refute_nil runner.instance_variable_get(:@recv_eval_proc)
  end

  it "CLI flags take precedence over registered procs" do
    OMQ.outgoing { raise "should not be called" }

    runner = OMQ::CLI::PushRunner.new(
      make_config(type_name: "push", send_expr: "'cli_wins'"),
      OMQ::PUSH
    )
    runner.send(:compile_expr)

    result = runner.send(:eval_send_expr, ["anything"])
    assert_equal ["cli_wins"], result
  end

  it "uses registered proc when no CLI flag" do
    OMQ.incoming { $F.map(&:upcase) }

    runner = OMQ::CLI::PullRunner.new(
      make_config(type_name: "pull"),
      OMQ::PULL
    )
    runner.send(:compile_expr)

    result = runner.send(:eval_recv_expr, ["hello"])
    assert_equal ["HELLO"], result
  end

  it "registered outgoing works without incoming" do
    OMQ.outgoing { $F.map(&:upcase) }

    runner = OMQ::CLI::ReqRunner.new(
      make_config(type_name: "req"),
      OMQ::REQ
    )
    runner.send(:compile_expr)

    refute_nil runner.instance_variable_get(:@send_eval_proc)
    assert_nil runner.instance_variable_get(:@recv_eval_proc)
  end

  it "mixes registered proc on one direction with CLI flag on the other" do
    OMQ.incoming { $F.map(&:downcase) }

    runner = OMQ::CLI::ReqRunner.new(
      make_config(type_name: "req", send_expr: "$F.map(&:upcase)"),
      OMQ::REQ
    )
    runner.send(:compile_expr)

    send_result = runner.send(:eval_send_expr, ["Hello"])
    assert_equal ["HELLO"], send_result

    recv_result = runner.send(:eval_recv_expr, ["Hello"])
    assert_equal ["hello"], recv_result
  end
end


# ── BEGIN/END blocks ───────────────────────────────────────────────

describe "extract_blocks" do
  before do
    @runner = OMQ::CLI::PushRunner.new(
      make_config(type_name: "push"),
      OMQ::PUSH
    )
  end

  it "extracts BEGIN and END bodies" do
    expr, begin_body, end_body = @runner.send(:extract_blocks,
      'BEGIN{ @s = 0 } @s += 1 END{ puts @s }')
    assert_equal " @s = 0 ", begin_body
    assert_equal " puts @s ", end_body
    assert_equal "@s += 1", expr.strip
  end

  it "handles nested braces" do
    expr, begin_body, end_body = @runner.send(:extract_blocks,
      'BEGIN{ @h = {} } $F END{ @h.each { |k,v| puts k } }')
    assert_equal " @h = {} ", begin_body
    assert_equal " @h.each { |k,v| puts k } ", end_body
    assert_equal "$F", expr.strip
  end

  it "returns nil for missing blocks" do
    expr, begin_body, end_body = @runner.send(:extract_blocks, '$F')
    assert_nil begin_body
    assert_nil end_body
    assert_equal "$F", expr
  end

  it "handles BEGIN only" do
    _, begin_body, end_body = @runner.send(:extract_blocks,
      'BEGIN{ @x = 1 } $F')
    assert_equal " @x = 1 ", begin_body
    assert_nil end_body
  end

  it "handles END only" do
    _, begin_body, end_body = @runner.send(:extract_blocks,
      '$F END{ puts "done" }')
    assert_nil begin_body
    assert_equal ' puts "done" ', end_body
  end
end


# ── Output ──────────────────────────────────────────────────────────

describe "output" do
  before do
    @runner = OMQ::CLI::PullRunner.new(
      make_config(type_name: "pull"),
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


# ── Grace period with Range reconnect_interval ─────────────────────

describe "wait_for_peer grace period with range reconnect_ivl" do
  it "uses Range#begin for the grace sleep" do
    Sync do
      push = OMQ::PUSH.new(linger: 0)
      push.reconnect_interval = 0.05..1.0
      push.bind("tcp://127.0.0.1:0")
      port = push.last_tcp_port

      pull = OMQ::PULL.new(linger: 0)
      pull.connect("tcp://127.0.0.1:#{port}")

      config = make_config(
        type_name: "push",
        reconnect_ivl: 0.05..1.0,
        binds: ["tcp://127.0.0.1:#{port}"],
      )
      runner = OMQ::CLI::PushRunner.new(config, OMQ::PUSH)
      runner.instance_variable_set(:@sock, push)

      # Should not raise TypeError from sleep(Range)
      runner.send(:wait_for_peer)
    ensure
      push&.close
      pull&.close
    end
  end
end

# ── Config ──────────────────────────────────────────────────────────

describe "OMQ::CLI::Config" do
  it "is frozen" do
    config = make_config(type_name: "push")
    assert config.frozen?
  end

  it "knows send-only types" do
    assert make_config(type_name: "push").send_only?
    assert make_config(type_name: "pub").send_only?
    assert make_config(type_name: "scatter").send_only?
    assert make_config(type_name: "radio").send_only?
    refute make_config(type_name: "pull").send_only?
  end

  it "knows recv-only types" do
    assert make_config(type_name: "pull").recv_only?
    assert make_config(type_name: "sub").recv_only?
    assert make_config(type_name: "gather").recv_only?
    assert make_config(type_name: "dish").recv_only?
    refute make_config(type_name: "push").recv_only?
  end
end
