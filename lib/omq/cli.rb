# frozen_string_literal: true

require "optparse"
require_relative "cli/config"
require_relative "cli/formatter"
require_relative "cli/base_runner"
require_relative "cli/push_pull"
require_relative "cli/pub_sub"
require_relative "cli/scatter_gather"
require_relative "cli/radio_dish"
require_relative "cli/req_rep"
require_relative "cli/pair"
require_relative "cli/router_dealer"
require_relative "cli/channel"
require_relative "cli/client_server"
require_relative "cli/peer"
require_relative "cli/pipe"

module OMQ

  class << self
    attr_reader :outgoing_proc, :incoming_proc

    def outgoing(&block) = @outgoing_proc = block
    def incoming(&block) = @incoming_proc = block
  end


  module CLI
    SOCKET_TYPE_NAMES = %w[
      req rep pub sub push pull pair dealer router
      client server radio dish scatter gather channel peer
      pipe
    ].freeze


    RUNNER_MAP = {
      "push"    => [PushRunner,    :PUSH],
      "pull"    => [PullRunner,    :PULL],
      "pub"     => [PubRunner,     :PUB],
      "sub"     => [SubRunner,     :SUB],
      "req"     => [ReqRunner,     :REQ],
      "rep"     => [RepRunner,     :REP],
      "dealer"  => [DealerRunner,  :DEALER],
      "router"  => [RouterRunner,  :ROUTER],
      "pair"    => [PairRunner,    :PAIR],
      "client"  => [ClientRunner,  :CLIENT],
      "server"  => [ServerRunner,  :SERVER],
      "radio"   => [RadioRunner,   :RADIO],
      "dish"    => [DishRunner,    :DISH],
      "scatter" => [ScatterRunner, :SCATTER],
      "gather"  => [GatherRunner,  :GATHER],
      "channel" => [ChannelRunner, :CHANNEL],
      "peer"    => [PeerRunner,    :PEER],
      "pipe"    => [PipeRunner,    nil],
    }.freeze


    EXAMPLES = <<~'TEXT'
      ── Request / Reply ──────────────────────────────────────────

        ┌─────┐  "hello"    ┌─────┐
        │ REQ │────────────→│ REP │
        │     │←────────────│     │
        └─────┘  "HELLO"    └─────┘

        # terminal 1: echo server
        omq rep --bind tcp://:5555 --recv-eval '$F.map(&:upcase)'

        # terminal 2: send a request
        echo "hello" | omq req --connect tcp://localhost:5555

        # or over IPC (unix socket, single machine)
        omq rep --bind ipc:///tmp/echo.sock --echo &
        echo "hello" | omq req --connect ipc:///tmp/echo.sock

      ── Publish / Subscribe ──────────────────────────────────────

        ┌─────┐  "weather.nyc 72F"  ┌─────┐
        │ PUB │────────────────────→│ SUB │ --subscribe "weather."
        └─────┘                     └─────┘

        # terminal 1: subscriber (all topics by default)
        omq sub --bind tcp://:5556

        # terminal 2: publisher (needs --delay for subscription to propagate)
        echo "weather.nyc 72F" | omq pub --connect tcp://localhost:5556 --delay 1

      ── Periodic Publish ───────────────────────────────────────────

        ┌─────┐  "tick 1"   ┌─────┐
        │ PUB │──(every 1s)─→│ SUB │
        └─────┘              └─────┘

        # terminal 1: subscriber
        omq sub --bind tcp://:5556

        # terminal 2: publish a tick every second (wall-clock aligned)
        omq pub --connect tcp://localhost:5556 --delay 1 \
          --data "tick" --interval 1

        # 5 ticks, then exit
        omq pub --connect tcp://localhost:5556 --delay 1 \
          --data "tick" --interval 1 --count 5

      ── Pipeline ─────────────────────────────────────────────────

        ┌──────┐           ┌──────┐
        │ PUSH │──────────→│ PULL │
        └──────┘           └──────┘

        # terminal 1: worker
        omq pull --bind tcp://:5557

        # terminal 2: send tasks
        echo "task 1" | omq push --connect tcp://localhost:5557

        # or over IPC (unix socket)
        omq pull --bind ipc:///tmp/pipeline.sock &
        echo "task 1" | omq push --connect ipc:///tmp/pipeline.sock

      ── Pipe (PULL → eval → PUSH) ────────────────────────────────

        ┌──────┐         ┌──────┐         ┌──────┐
        │ PUSH │────────→│ pipe │────────→│ PULL │
        └──────┘         └──────┘         └──────┘

        # terminal 1: producer
        echo -e "hello\nworld" | omq push --bind ipc://@work

        # terminal 2: worker — uppercase each message
        omq pipe -c ipc://@work -c ipc://@sink -e '$F.map(&:upcase)'
        # terminal 3: collector
        omq pull --bind ipc://@sink

        # 4 Ractor workers in a single process (-P)
        omq pipe -c ipc://@work -c ipc://@sink -P 4 \
          -r ./fib.rb -e 'fib(Integer($_)).to_s'

        # exit when producer disconnects (--transient)
        omq pipe -c ipc://@work -c ipc://@sink --transient \
          -e '$F.map(&:upcase)'

        # fan-in: multiple sources → one sink
        omq pipe --in -c ipc://@work1 -c ipc://@work2 \
          --out -c ipc://@sink -e '$F.map(&:upcase)'

        # fan-out: one source → multiple sinks (round-robin)
        omq pipe --in -b tcp://:5555 \
          --out -c ipc://@sink1 -c ipc://@sink2 -e '$F'

      ── CLIENT / SERVER (draft) ──────────────────────────────────

        ┌────────┐  "hello"   ┌────────┐
        │ CLIENT │───────────→│ SERVER │ --recv-eval '$F.map(&:upcase)'
        │        │←───────────│        │
        └────────┘  "HELLO"   └────────┘

        # terminal 1: upcasing server
        omq server --bind tcp://:5555 --recv-eval '$F.map(&:upcase)'

        # terminal 2: client
        echo "hello" | omq client --connect tcp://localhost:5555

      ── Formats ──────────────────────────────────────────────────

        # ascii (default) — non-printable replaced with dots
        omq pull --bind tcp://:5557 --ascii

        # quoted — lossless, round-trippable (uses String#dump escaping)
        omq pull --bind tcp://:5557 --quoted

        # JSON Lines — structured, multipart as arrays
        echo '["key","value"]' | omq push --connect tcp://localhost:5557 --jsonl
        omq pull --bind tcp://:5557 --jsonl

        # multipart via tabs
        printf "routing-key\tpayload" | omq push --connect tcp://localhost:5557

      ── Compression ──────────────────────────────────────────────

        # both sides must use --compress
        omq pull --bind tcp://:5557 --compress &
        echo "compressible data" | omq push --connect tcp://localhost:5557 --compress

      ── CURVE Encryption ─────────────────────────────────────────

        # server (prints OMQ_SERVER_KEY=...)
        omq rep --bind tcp://:5555 --echo --curve-server

        # client (paste the server's key)
        echo "secret" | omq req --connect tcp://localhost:5555 \
          --curve-server-key '<key from server>'

      ── ROUTER / DEALER ──────────────────────────────────────────

        ┌────────┐          ┌────────┐
        │ DEALER │─────────→│ ROUTER │
        │ id=w1  │          │        │
        └────────┘          └────────┘

        # terminal 1: router shows identity + message
        omq router --bind tcp://:5555

        # terminal 2: dealer with identity
        echo "hello" | omq dealer --connect tcp://localhost:5555 \
          --identity worker-1

      ── Ruby Eval ────────────────────────────────────────────────

        # filter incoming: only pass messages containing "error"
        omq pull --bind tcp://:5557 \
          --recv-eval '$F.first.include?("error") ? $F : nil'

        # transform incoming with gems
        omq sub --connect tcp://localhost:5556 --require json \
          --recv-eval 'JSON.parse($F.first)["temperature"]'

        # require a local file, use its methods
        omq rep --bind tcp://:5555 --require ./transform.rb \
          --recv-eval 'upcase_all($F)'

        # next skips, break stops — regexps match against $_
        omq pull --bind tcp://:5557 \
          --recv-eval 'next if /^#/; break if /quit/; $F'

        # BEGIN/END blocks (like awk) — accumulate and summarize
        omq pull --bind tcp://:5557 \
          --recv-eval 'BEGIN{ @sum = 0 } @sum += Integer($_); next END{ puts @sum }'

        # transform outgoing messages
        echo hello | omq push --connect tcp://localhost:5557 \
          --send-eval '$F.map(&:upcase)'

        # REQ: transform request and reply independently
        echo hello | omq req --connect tcp://localhost:5555 \
          --send-eval '$F.map(&:upcase)' --recv-eval '$_'

      ── Script Handlers (-r) ────────────────────────────────────

        # handler.rb — register transforms from a file
        #   db = PG.connect("dbname=app")
        #   OMQ.incoming { db.exec($F.first).values.flatten }
        #   at_exit { db.close }
        omq pull --bind tcp://:5557 -r ./handler.rb

        # combine script handlers with inline eval
        omq req -c tcp://localhost:5555 -r ./handler.rb \
          --send-eval '$F.map(&:upcase)'

        # OMQ.outgoing { ... }   — registered outgoing transform
        # OMQ.incoming { ... }   — registered incoming transform
        # CLI flags (-e/-E) override registered handlers
    TEXT

    module_function


    # Displays text through the system pager, or prints directly
    # when stdout is not a terminal.
    #
    def page(text)
      if $stdout.tty?
        if ENV["PAGER"]
          pager = ENV["PAGER"]
        else
          ENV["LESS"] ||= "-FR"
          pager = "less"
        end
        IO.popen(pager, "w") { |io| io.puts text }
      else
        puts text
      end
    rescue Errno::ENOENT
      puts text
    rescue Errno::EPIPE
      # user quit pager early
    end


    # Parses CLI arguments, validates options, and runs the main
    # event loop inside an Async reactor.
    #
    def run(argv = ARGV)
      config = build_config(argv)

      require_relative "../omq"
      require "async"
      require "json"
      require "console"

      validate_gems!(config)

      trap("INT")  { Process.exit!(0) }
      trap("TERM") { Process.exit!(0) }

      Console.logger = Console::Logger.new(Console::Output::Null.new) unless config.verbose

      runner_class, socket_sym = RUNNER_MAP.fetch(config.type_name)

      Async do |task|
        runner = if socket_sym
                   runner_class.new(config, OMQ.const_get(socket_sym))
                 else
                   runner_class.new(config)
                 end
        runner.call(task)
      rescue IO::TimeoutError, Async::TimeoutError
        $stderr.puts "omq: timeout" unless config.quiet
        exit 2
      rescue OMQ::SocketDeadError => e
        $stderr.puts "omq: #{e.cause.class}: #{e.cause.message}"
        exit 1
      rescue ::Socket::ResolutionError => e
        $stderr.puts "omq: #{e.message}"
        exit 1
      end
    end


    # Builds a frozen Config from command-line arguments.
    #
    def build_config(argv)
      opts = parse_options(argv)
      validate!(opts)

      opts[:has_msgpack]  = begin; require "msgpack"; true; rescue LoadError; false; end
      opts[:has_zstd]     = begin; require "zstd-ruby"; true; rescue LoadError; false; end
      opts[:stdin_is_tty] = $stdin.tty?

      Ractor.make_shareable(Config.new(**opts))
    end


    # Parses command-line arguments into a mutable options hash.
    #
    def parse_options(argv)
      opts = {
        endpoints:        [],
        connects:         [],
        binds:            [],
        in_endpoints:     [],
        out_endpoints:    [],
        data:             nil,
        file:             nil,
        format:           :ascii,
        subscribes:       [],
        joins:            [],
        group:            nil,
        identity:         nil,
        target:           nil,
        interval:         nil,
        count:            nil,
        delay:            nil,
        timeout:          nil,
        linger:           5,
        reconnect_ivl:    nil,
        heartbeat_ivl:    nil,
        conflate:         false,
        compress:         false,
        send_expr:        nil,
        recv_expr:        nil,
        parallel:         nil,
        transient:        false,
        verbose:          false,
        quiet:            false,
        echo:             false,
        curve_server:     false,
        curve_server_key: nil,
      }

      pipe_side = nil  # nil = legacy positional mode; :in/:out = modal

      parser = OptionParser.new do |o|
        o.banner = "Usage: omq TYPE [options]\n\n" \
                   "Types:    req, rep, pub, sub, push, pull, pair, dealer, router\n" \
                   "Draft:    client, server, radio, dish, scatter, gather, channel, peer\n" \
                   "Virtual:  pipe (PULL → eval → PUSH)\n\n"

        o.separator "Connection:"
        o.on("-c", "--connect URL", "Connect to endpoint (repeatable)") { |v|
          ep = Endpoint.new(v, false)
          case pipe_side
          when :in  then opts[:in_endpoints] << ep
          when :out then opts[:out_endpoints] << ep
          else           opts[:endpoints] << ep; opts[:connects] << v
          end
        }
        o.on("-b", "--bind URL", "Bind to endpoint (repeatable)") { |v|
          ep = Endpoint.new(v, true)
          case pipe_side
          when :in  then opts[:in_endpoints] << ep
          when :out then opts[:out_endpoints] << ep
          else           opts[:endpoints] << ep; opts[:binds] << v
          end
        }
        o.on("--in",  "Pipe: subsequent -b/-c attach to input (PULL) side")  { pipe_side = :in }
        o.on("--out", "Pipe: subsequent -b/-c attach to output (PUSH) side") { pipe_side = :out }

        o.separator "\nData source (REP: reply source):"
        o.on(      "--echo",        "Echo received messages back (REP)")   { opts[:echo] = true }
        o.on("-D", "--data DATA",   "Message data (literal string)")      { |v| opts[:data] = v }
        o.on("-F", "--file FILE",   "Read message from file (- = stdin)") { |v| opts[:file] = v }

        o.separator "\nFormat (input + output):"
        o.on("-A", "--ascii",   "Tab-separated frames, safe ASCII (default)") { opts[:format] = :ascii }
        o.on("-Q", "--quoted",  "C-style quoted with escapes")                { opts[:format] = :quoted }
        o.on(      "--raw",     "Raw binary, no framing")                     { opts[:format] = :raw }
        o.on("-J", "--jsonl",   "JSON Lines (array of strings per line)")     { opts[:format] = :jsonl }
        o.on(      "--msgpack",  "MessagePack arrays (binary stream)")         { opts[:format] = :msgpack }
        o.on("-M", "--marshal", "Ruby Marshal stream (binary, Array<String>)") { opts[:format] = :marshal }

        o.separator "\nSubscription/groups:"
        o.on("-s", "--subscribe PREFIX", "Subscribe prefix (SUB, default all)")       { |v| opts[:subscribes] << v }
        o.on("-j", "--join GROUP",       "Join group (repeatable, DISH only)")       { |v| opts[:joins] << v }
        o.on("-g", "--group GROUP",      "Publish group (RADIO only)")              { |v| opts[:group] = v }

        o.separator "\nIdentity/routing:"
        o.on("--identity ID", "Set socket identity (DEALER/ROUTER)")                      { |v| opts[:identity] = v }
        o.on("--target ID",   "Target peer (ROUTER/SERVER/PEER, 0x prefix for binary)")   { |v| opts[:target] = v }

        o.separator "\nTiming:"
        o.on("-i", "--interval SECS", Float, "Repeat interval")          { |v| opts[:interval] = v }
        o.on("-n", "--count COUNT",   Integer, "Max iterations (0=inf)") { |v| opts[:count] = v }
        o.on("-d", "--delay SECS",    Float, "Delay before first send")  { |v| opts[:delay] = v }
        o.on("-t", "--timeout SECS", Float, "Send/receive timeout")       { |v| opts[:timeout] = v }
        o.on("-l", "--linger SECS",  Float, "Drain time on close (default 5)") { |v| opts[:linger] = v }
        o.on("--reconnect-ivl IVL", "Reconnect interval: SECS or MIN..MAX (default 0.1)") { |v|
          opts[:reconnect_ivl] = if v.include?("..")
                                   lo, hi = v.split("..", 2)
                                   Float(lo)..Float(hi)
                                 else
                                   Float(v)
                                 end
        }
        o.on("--heartbeat-ivl SECS", Float, "ZMTP heartbeat interval (detects dead peers)") { |v| opts[:heartbeat_ivl] = v }

        o.separator "\nDelivery:"
        o.on("--conflate", "Keep only last message per subscriber (PUB/RADIO)") { opts[:conflate] = true }

        o.separator "\nCompression:"
        o.on("-z", "--compress", "Zstandard compression per frame") { opts[:compress] = true }

        o.separator "\nProcessing (-e = incoming, -E = outgoing):"
        o.on("-e", "--recv-eval EXPR", "Eval Ruby for each incoming message ($F = parts)") { |v| opts[:recv_expr] = v }
        o.on("-E", "--send-eval EXPR", "Eval Ruby for each outgoing message ($F = parts)") { |v| opts[:send_expr] = v }
        o.on("-r", "--require LIB",  "Require lib/file; scripts can register OMQ.outgoing/incoming") { |v|
          require_relative "../omq" unless defined?(OMQ::VERSION)
          v.start_with?("./", "../") ? require(File.expand_path(v)) : require(v)
        }
        o.on("-P", "--parallel [N]", Integer, "Parallel Ractor workers (pipe only, default: nproc)") { |v|
          require "etc"
          opts[:parallel] = v || Etc.nprocessors
        }

        o.separator "\nCURVE encryption (requires omq-curve gem):"
        o.on("--curve-server",         "Enable CURVE as server (generates keypair)") { opts[:curve_server] = true }
        o.on("--curve-server-key KEY", "Enable CURVE as client (server's Z85 public key)") { |v| opts[:curve_server_key] = v }
        o.separator "  Env vars: OMQ_SERVER_KEY (client), OMQ_SERVER_PUBLIC + OMQ_SERVER_SECRET (server)"

        o.separator "\nOther:"
        o.on("-v", "--verbose",     "Print connection events to stderr") { opts[:verbose] = true }
        o.on("-q", "--quiet",       "Suppress message output")          { opts[:quiet] = true }
        o.on(      "--transient",   "Exit when all peers disconnect")   { opts[:transient] = true }
        o.on("-V", "--version")     { require_relative "../omq"; puts "omq #{OMQ::VERSION}"; exit }
        o.on("-h")                  { puts o; exit }
        o.on(      "--help")        { page "#{o}\n#{EXAMPLES}"; exit }
        o.on(      "--examples")    { page EXAMPLES; exit }

        o.separator "\nExit codes: 0 = success, 1 = error, 2 = timeout"
      end

      begin
        parser.parse!(argv)
      rescue OptionParser::ParseError => e
        abort e.message
      end

      type_name = argv.shift
      abort parser.to_s unless type_name
      unless SOCKET_TYPE_NAMES.include?(type_name.downcase)
        abort "Unknown socket type: #{type_name}. Known: #{SOCKET_TYPE_NAMES.join(', ')}"
      end

      opts[:type_name] = type_name.downcase

      normalize    = ->(url) { url.sub(%r{\Atcp://\*:}, "tcp://0.0.0.0:").sub(%r{\Atcp://:}, "tcp://localhost:") }
      normalize_ep = ->(ep) { Endpoint.new(normalize.call(ep.url), ep.bind?) }
      opts[:binds].map!(&normalize)
      opts[:connects].map!(&normalize)
      opts[:endpoints].map!(&normalize_ep)
      opts[:in_endpoints].map!(&normalize_ep)
      opts[:out_endpoints].map!(&normalize_ep)

      opts
    end


    # Validates option combinations.
    #
    def validate!(opts)
      type_name = opts[:type_name]

      if type_name == "pipe"
        has_in_out = opts[:in_endpoints].any? || opts[:out_endpoints].any?
        if has_in_out
          abort "pipe --in requires at least one endpoint"              if opts[:in_endpoints].empty?
          abort "pipe --out requires at least one endpoint"             if opts[:out_endpoints].empty?
          abort "pipe: don't mix --in/--out with bare -b/-c endpoints"  unless opts[:endpoints].empty?
        else
          abort "pipe requires exactly 2 endpoints (pull-side and push-side), or use --in/--out" if opts[:endpoints].size != 2
        end
      else
        abort "--in/--out are only valid for pipe" if opts[:in_endpoints].any? || opts[:out_endpoints].any?
        abort "At least one --connect or --bind is required" if opts[:connects].empty? && opts[:binds].empty?
      end
      abort "--data and --file are mutually exclusive"        if opts[:data] && opts[:file]
      abort "--subscribe is only valid for SUB"               if !opts[:subscribes].empty? && type_name != "sub"
      abort "--join is only valid for DISH"                   if !opts[:joins].empty? && type_name != "dish"
      abort "--group is only valid for RADIO"                 if opts[:group] && type_name != "radio"
      abort "--identity is only valid for DEALER/ROUTER"      if opts[:identity] && !%w[dealer router].include?(type_name)
      abort "--target is only valid for ROUTER/SERVER/PEER"   if opts[:target] && !%w[router server peer].include?(type_name)
      abort "--conflate is only valid for PUB/RADIO"          if opts[:conflate] && !%w[pub radio].include?(type_name)
      abort "--recv-eval is not valid for send-only sockets (use --send-eval / -E)" if opts[:recv_expr] && SEND_ONLY.include?(type_name)
      abort "--send-eval is not valid for recv-only sockets (use --recv-eval / -e)" if opts[:send_expr] && RECV_ONLY.include?(type_name)
      abort "--send-eval and --target are mutually exclusive"  if opts[:send_expr] && opts[:target]

      if opts[:parallel]
        abort "-P/--parallel is only valid for pipe"                                    unless type_name == "pipe"
        abort "-P/--parallel must be >= 2"                                              if opts[:parallel] < 2
        all_pipe_eps = opts[:in_endpoints] + opts[:out_endpoints] + opts[:endpoints]
        abort "-P/--parallel requires all endpoints to use --connect (not --bind)" if all_pipe_eps.any?(&:bind?)
      end

      (opts[:connects] + opts[:binds]).each do |url|
        abort "inproc not supported, use tcp:// or ipc://" if url.include?("inproc://")
      end
    end


    # Validates that required gems are available.
    #
    def validate_gems!(config)
      abort "--msgpack requires the msgpack gem"    if config.format == :msgpack && !config.has_msgpack
      abort "--compress requires the zstd-ruby gem" if config.compress && !config.has_zstd

      if config.recv_only? && (config.data || config.file)
        abort "--data/--file not valid for #{config.type_name} (receive-only)"
      end
    end
  end
end
