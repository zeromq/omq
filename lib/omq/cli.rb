# frozen_string_literal: true

require "optparse"

module OMQ
  module CLI
    SOCKET_TYPE_NAMES = %w[
      req rep pub sub push pull pair dealer router
      client server radio dish scatter gather channel peer
    ].freeze

    EXAMPLES = <<~'TEXT'
      ── Request / Reply ──────────────────────────────────────────

        ┌─────┐  "hello"    ┌─────┐
        │ REQ │────────────→│ REP │
        │     │←────────────│     │
        └─────┘  "HELLO"    └─────┘

        # terminal 1: echo server
        omqcat rep --bind tcp://:5555 --eval '$F.map(&:upcase)'

        # terminal 2: send a request
        echo "hello" | omqcat req --connect tcp://localhost:5555

        # or over IPC (unix socket, single machine)
        omqcat rep --bind ipc:///tmp/echo.sock --echo &
        echo "hello" | omqcat req --connect ipc:///tmp/echo.sock

      ── Publish / Subscribe ──────────────────────────────────────

        ┌─────┐  "weather.nyc 72F"  ┌─────┐
        │ PUB │────────────────────→│ SUB │ --subscribe "weather."
        └─────┘                     └─────┘

        # terminal 1: subscriber (all topics by default)
        omqcat sub --bind tcp://:5556

        # terminal 2: publisher (needs --delay for subscription to propagate)
        echo "weather.nyc 72F" | omqcat pub --connect tcp://localhost:5556 --delay 1

      ── Pipeline ─────────────────────────────────────────────────

        ┌──────┐           ┌──────┐
        │ PUSH │──────────→│ PULL │
        └──────┘           └──────┘

        # terminal 1: worker
        omqcat pull --bind tcp://:5557

        # terminal 2: send tasks
        echo "task 1" | omqcat push --connect tcp://localhost:5557

        # or over IPC (unix socket)
        omqcat pull --bind ipc:///tmp/pipeline.sock &
        echo "task 1" | omqcat push --connect ipc:///tmp/pipeline.sock

      ── CLIENT / SERVER (draft) ──────────────────────────────────

        ┌────────┐  "hello"   ┌────────┐
        │ CLIENT │───────────→│ SERVER │ --eval '$F.map(&:upcase)'
        │        │←───────────│        │
        └────────┘  "HELLO"   └────────┘

        # terminal 1: upcasing server
        omqcat server --bind tcp://:5555 --eval '$F.map(&:upcase)'

        # terminal 2: client
        echo "hello" | omqcat client --connect tcp://localhost:5555

      ── Formats ──────────────────────────────────────────────────

        # ascii (default) — non-printable replaced with dots
        omqcat pull --bind tcp://:5557 --ascii

        # quoted — lossless, round-trippable (uses String#dump escaping)
        omqcat pull --bind tcp://:5557 --quoted

        # JSON Lines — structured, multipart as arrays
        echo '["key","value"]' | omqcat push --connect tcp://localhost:5557 --jsonl
        omqcat pull --bind tcp://:5557 --jsonl

        # multipart via tabs
        printf "routing-key\tpayload" | omqcat push --connect tcp://localhost:5557

      ── Compression ──────────────────────────────────────────────

        # both sides must use --compress
        omqcat pull --bind tcp://:5557 --compress &
        echo "compressible data" | omqcat push --connect tcp://localhost:5557 --compress

      ── CURVE Encryption ─────────────────────────────────────────

        # server (prints OMQ_SERVER_KEY=...)
        omqcat rep --bind tcp://:5555 --echo --curve-server

        # client (paste the server's key)
        echo "secret" | omqcat req --connect tcp://localhost:5555 \
          --curve-server-key '<key from server>'

      ── ROUTER / DEALER ──────────────────────────────────────────

        ┌────────┐          ┌────────┐
        │ DEALER │─────────→│ ROUTER │
        │ id=w1  │          │        │
        └────────┘          └────────┘

        # terminal 1: router shows identity + message
        omqcat router --bind tcp://:5555

        # terminal 2: dealer with identity
        echo "hello" | omqcat dealer --connect tcp://localhost:5555 \
          --identity worker-1

      ── Ruby Eval ────────────────────────────────────────────────

        # filter: only pass messages containing "error"
        omqcat pull --bind tcp://:5557 \
          --eval '$F.first.include?("error") ? $F : nil'

        # transform with gems
        omqcat sub --connect tcp://localhost:5556 --require json \
          --eval 'JSON.parse($F.first)["temperature"]'

        # require a local file, use its methods in --eval
        omqcat rep --bind tcp://:5555 --require ./transform.rb \
          --eval 'upcase_all($F)'
    TEXT

    module_function

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

    def run(argv = ARGV)
      opts = parse_options(argv)
      validate!(opts)

      require "omq"
      require "async"
      require "json"
      require "console"

      klass = resolve_socket_class(opts[:type_name])

      opts[:has_msgpack] = begin; require "msgpack"; true; rescue LoadError; false; end
      opts[:has_zstd]    = begin; require "zstd-ruby"; true; rescue LoadError; false; end

      validate_gems!(opts)

      trap("INT")  { Process.exit!(0) }
      trap("TERM") { Process.exit!(0) }

      Console.logger = Console::Logger.new(Console::Output::Null.new) unless opts[:verbose]

      Async do |task|
        runner = Runner.new(opts, klass)
        runner.call(task)
      rescue IO::TimeoutError
        $stderr.puts "omqcat: timeout" unless opts[:quiet]
        exit 2
      end
    end

    def parse_options(argv)
      opts = {
        connects:     [],
        binds:        [],
        data:         nil,
        file:         nil,
        format:       :ascii,
        subscribes:   [],
        joins:        [],
        group:        nil,
        identity:     nil,
        target:       nil,
        interval:     nil,
        count:        nil,
        delay:        nil,
        timeout:      nil,
        linger:       5,
        conflate:     false,
        compress:     false,
        expr:         nil,
        transient: false,
        verbose:      false,
        quiet:        false,
      }

      parser = OptionParser.new do |o|
        o.banner = "Usage: omqcat TYPE [options]\n\n" \
                   "Types: req, rep, pub, sub, push, pull, pair, dealer, router\n" \
                   "Draft: client, server, radio, dish, scatter, gather, channel, peer\n\n"

        o.separator "Connection:"
        o.on("-c", "--connect URL", "Connect to endpoint (repeatable)")   { |v| opts[:connects] << v }
        o.on("-b", "--bind URL",    "Bind to endpoint (repeatable)")      { |v| opts[:binds] << v }

        o.separator "\nData source (REP: reply source):"
        o.on(      "--echo",        "Echo received messages back (REP)")   { opts[:echo] = true }
        o.on("-D", "--data DATA",   "Message data (literal string)")      { |v| opts[:data] = v }
        o.on("-F", "--file FILE",   "Read message from file (- = stdin)") { |v| opts[:file] = v }

        o.separator "\nFormat (input + output):"
        o.on("-A", "--ascii",   "Tab-separated frames, safe ASCII (default)") { opts[:format] = :ascii }
        o.on("-Q", "--quoted",  "C-style quoted with escapes")                { opts[:format] = :quoted }
        o.on(      "--raw",     "Raw binary, no framing")                     { opts[:format] = :raw }
        o.on("-J", "--jsonl",   "JSON Lines (array of strings per line)")     { opts[:format] = :jsonl }
        o.on(      "--msgpack", "MessagePack arrays (binary stream)")         { opts[:format] = :msgpack }

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

        o.separator "\nDelivery:"
        o.on("--conflate", "Keep only last message per subscriber (PUB/RADIO)") { opts[:conflate] = true }

        o.separator "\nCompression:"
        o.on("-z", "--compress", "Zstandard compression per frame") { opts[:compress] = true }

        o.separator "\nProcessing:"
        o.on("-e", "--eval EXPR",    "Eval Ruby for each message ($F = parts)")   { |v| opts[:expr] = v }
        o.on("-r", "--require LIB", "Require library or file (-r./lib.rb)")    { |v|
          v.start_with?("./", "../") ? require(File.expand_path(v)) : require(v)
        }

        o.separator "\nCURVE encryption (requires omq-curve gem):"
        o.on("--curve-server",         "Enable CURVE as server (generates keypair)") { opts[:curve_server] = true }
        o.on("--curve-server-key KEY", "Enable CURVE as client (server's Z85 public key)") { |v| opts[:curve_server_key] = v }
        o.separator "  Env vars: OMQ_SERVER_KEY (client), OMQ_SERVER_PUBLIC + OMQ_SERVER_SECRET (server)"

        o.separator "\nOther:"
        o.on("-v", "--verbose",            "Print connection events to stderr")      { opts[:verbose] = true }
        o.on("-q", "--quiet",              "Suppress message output")                { opts[:quiet] = true }
        o.on(      "--transient", "Exit when all peers have disconnected")            { opts[:transient] = true }
        o.on("-V", "--version")                                      { require "omq"; puts "omqcat #{OMQ::VERSION}"; exit }
        o.on("-h")                                                   { puts o; exit }
        o.on(      "--help")                                         { page "#{o}\n#{EXAMPLES}"; exit }
        o.on(      "--examples")                                     { page EXAMPLES; exit }

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
      opts
    end

    def resolve_socket_class(type_name)
      OMQ.const_get(type_name.upcase)
    end

    def validate!(opts)
      type_name = opts[:type_name]

      abort "At least one --connect or --bind is required"   if opts[:connects].empty? && opts[:binds].empty?
      abort "--data and --file are mutually exclusive"        if opts[:data] && opts[:file]
      abort "--subscribe is only valid for SUB"               if !opts[:subscribes].empty? && type_name != "sub"
      abort "--join is only valid for DISH"                   if !opts[:joins].empty? && type_name != "dish"
      abort "--group is only valid for RADIO"                 if opts[:group] && type_name != "radio"
      abort "--identity is only valid for DEALER/ROUTER"      if opts[:identity] && !%w[dealer router].include?(type_name)
      abort "--target is only valid for ROUTER/SERVER/PEER"   if opts[:target] && !%w[router server peer].include?(type_name)
      abort "--conflate is only valid for PUB/RADIO"          if opts[:conflate] && !%w[pub radio].include?(type_name)

      (opts[:connects] + opts[:binds]).each do |url|
        abort "inproc not supported, use tcp:// or ipc://" if url.include?("inproc://")
      end
    end

    def validate_gems!(opts)
      abort "--msgpack requires the msgpack gem"    if opts[:format] == :msgpack && !opts[:has_msgpack]
      abort "--compress requires the zstd-ruby gem" if opts[:compress] && !opts[:has_zstd]

      if Runner::RECV_ONLY_NAMES.include?(opts[:type_name]) && (opts[:data] || opts[:file])
        abort "--data/--file not valid for #{opts[:type_name]} (receive-only)"
      end
    end

    # Handles encoding/decoding messages in the configured format,
    # plus optional Zstandard compression.
    class Formatter
      def initialize(format, compress: false)
        @format   = format
        @compress = compress
      end

      def encode(parts)
        case @format
        when :ascii
          parts.map { |p| p.b.gsub(/[^[:print:]\t]/, ".") }.join("\t") + "\n"
        when :quoted
          parts.map { |p| p.b.dump[1..-2] }.join("\t") + "\n"
        when :raw
          parts.join
        when :jsonl
          JSON.generate(parts) + "\n"
        when :msgpack
          MessagePack.pack(parts)
        end
      end

      def decode(line)
        case @format
        when :ascii
          line.chomp.split("\t")
        when :quoted
          line.chomp.split("\t").map { |p| "\"#{p}\"".undump }
        when :raw
          [line]
        when :jsonl
          arr = JSON.parse(line.chomp)
          abort "JSON Lines input must be an array of strings" unless arr.is_a?(Array) && arr.all? { |e| e.is_a?(String) }
          arr
        end
      end

      def decode_msgpack(io)
        @msgpack_unpacker ||= MessagePack::Unpacker.new(io)
        @msgpack_unpacker.read
      rescue EOFError
        nil
      end

      def compress(parts)
        @compress ? parts.map { |p| Zstd.compress(p) } : parts
      end

      def decompress(parts)
        @compress ? parts.map { |p| Zstd.decompress(p) } : parts
      end
    end

    # Runs the main event loop for a given socket type.
    class Runner
      SEND_ONLY_NAMES = %w[pub push scatter radio].freeze
      RECV_ONLY_NAMES = %w[sub pull gather dish].freeze

      def initialize(opts, klass)
        @opts      = opts
        @klass     = klass
        @type_name = opts[:type_name]
        @fmt       = Formatter.new(opts[:format], compress: opts[:compress])

        normalize = ->(url) { url.sub(%r{\Atcp://:}, "tcp://*:") }
        @opts[:connects].map!(&normalize)
        @opts[:binds].map!(&normalize)
      end

      def call(task)
        sock_opts = { linger: @opts[:linger] }
        sock_opts[:conflate] = true if @opts[:conflate] && %w[pub radio].include?(@type_name)
        @sock = @klass.new(nil, **sock_opts)
        @sock.recv_timeout = @opts[:timeout] if @opts[:timeout]
        @sock.send_timeout = @opts[:timeout] if @opts[:timeout]
        @sock.identity     = @opts[:identity] if @opts[:identity]

        setup_curve

        @opts[:binds].each do |url|
          @sock.bind(url)
          log "Bound to #{@sock.last_endpoint}" if @opts[:verbose]
        end

        @opts[:connects].each do |url|
          @sock.connect(url)
          log "Connecting to #{url}" if @opts[:verbose]
        end

        setup_subscriptions
        compile_expr
        if @opts[:transient]
          start_disconnect_monitor(task)
          Async::Task.current.yield  # let monitor start waiting
        end

        sleep(@opts[:delay]) if @opts[:delay] && recv_only?

        run_loop(task)
      ensure
        @sock&.close
      end

      private

      def send_only?
        SEND_ONLY_NAMES.include?(@type_name)
      end

      def recv_only?
        RECV_ONLY_NAMES.include?(@type_name)
      end

      def start_disconnect_monitor(task)
        @transient_barrier = Async::Promise.new
        task.async do
          @transient_barrier.wait
          # Wait until all peers are gone. If they already left before
          # the barrier, connection_count is 0 and we exit immediately —
          # but that's fine because we've already sent/received a message.
          @sock.all_peers_gone.wait unless @sock.connection_count == 0
          log "All peers disconnected, exiting" if @opts[:verbose]
          @sock.reconnect_enabled = false
          task.stop
        end
      end

      def transient_ready!
        if @opts[:transient] && !@transient_barrier.resolved?
          @transient_barrier.resolve(true)
        end
      end

      # ── Socket setup ──────────────────────────────────────────────

      def setup_subscriptions
        case @type_name
        when "sub"
          prefixes = @opts[:subscribes].empty? ? [""] : @opts[:subscribes]
          prefixes.each { |p| @sock.subscribe(p) }
        when "dish"
          @opts[:joins].each { |g| @sock.join(g) }
        end
      end

      def setup_curve
        server_key_z85 = @opts[:curve_server_key] || ENV["OMQ_SERVER_KEY"]
        server_mode    = @opts[:curve_server] || (ENV["OMQ_SERVER_PUBLIC"] && ENV["OMQ_SERVER_SECRET"])

        if server_key_z85
          require "omq/curve"
          server_key = OMQ::Z85.decode(server_key_z85)
          client_key = RbNaCl::PrivateKey.generate
          @sock.mechanism = OMQ::Curve.client(
            client_key.public_key.to_s, client_key.to_s, server_key: server_key
          )
        elsif server_mode
          require "omq/curve"
          if ENV["OMQ_SERVER_PUBLIC"] && ENV["OMQ_SERVER_SECRET"]
            server_pub = OMQ::Z85.decode(ENV["OMQ_SERVER_PUBLIC"])
            server_sec = OMQ::Z85.decode(ENV["OMQ_SERVER_SECRET"])
          else
            key        = RbNaCl::PrivateKey.generate
            server_pub = key.public_key.to_s
            server_sec = key.to_s
          end
          @sock.mechanism = OMQ::Curve.server(server_pub, server_sec)
          $stderr.puts "OMQ_SERVER_KEY='#{OMQ::Z85.encode(server_pub)}'"
        end
      rescue LoadError
        abort "omq-curve gem required for CURVE encryption: gem install omq-curve"
      end

      # ── Loop dispatch ──────────────────────────────────────────────

      def run_loop(task)
        case @type_name
        when "req", "client"
          req_loop
        when "rep"
          rep_loop
        when "router"
          router_loop(task)
        when "server", "peer"
          if @opts[:echo] || @opts[:expr] || @opts[:data] || @opts[:file] || !$stdin.tty?
            server_reply_loop
          else
            server_loop(task)
          end
        else
          if send_only?
            send_loop
          elsif recv_only?
            recv_loop
          elsif @opts[:data] || @opts[:file]
            send_loop
          else
            pair_loop(task)
          end
        end
      end

      # ── Loop implementations ───────────────────────────────────────

      def send_loop
        i = 0
        if @opts[:data] || @opts[:file]
          loop do
            parts = read_next
            break unless parts
            parts = eval_expr(parts)
            sleep(@opts[:delay]) if @opts[:delay] && i == 0
            send_msg(parts) if parts
            i += 1
            break if count_reached?(i)
            if @opts[:interval]
              sleep(@opts[:interval])
            else
              break
            end
          end
        else
          loop do
            parts = read_next
            break unless parts
            parts = eval_expr(parts)
            sleep(@opts[:delay]) if @opts[:delay] && i == 0
            send_msg(parts) if parts
            i += 1
            break if count_reached?(i)
            sleep(@opts[:interval]) if @opts[:interval]
          end
        end
      end

      def recv_loop
        i = 0
        loop do
          parts = recv_msg
          parts = eval_expr(parts)
          output(parts)
          i += 1
          break if count_reached?(i)
        end
      end

      def req_loop
        i = 0
        loop do
          parts = read_next
          break unless parts
          sleep(@opts[:delay]) if @opts[:delay] && i == 0
          send_msg(parts)
          reply = recv_msg
          reply = eval_expr(reply)
          output(reply)
          i += 1
          break if count_reached?(i)
          if @opts[:interval]
            sleep(@opts[:interval])
          elsif !@opts[:data] && !@opts[:file]
            next
          else
            break
          end
        end
      end

      def rep_loop
        i = 0
        loop do
          msg = recv_msg
          if @opts[:expr]
            reply = eval_expr(msg)
            output(reply)
            send_msg(reply || [""])
          elsif @opts[:echo]
            output(msg)
            send_msg(msg)
          elsif @opts[:data] || @opts[:file] || !$stdin.tty?
            reply = read_next
            break unless reply
            output(msg)
            send_msg(reply)
          else
            abort "REP needs a reply source: --echo, --data, --file, -e, or stdin pipe"
          end
          i += 1
          break if count_reached?(i)
        end
      end

      def pair_loop(task)
        receiver = task.async do
          i = 0
          loop do
            parts = recv_msg
            parts = eval_expr(parts)
            output(parts)
            i += 1
            break if count_reached?(i)
          end
        end

        sender = task.async do
          i = 0
          loop do
            parts = read_next
            break unless parts
            parts = eval_expr(parts)
            sleep(@opts[:delay]) if @opts[:delay] && i == 0
            send_msg(parts) if parts
            i += 1
            break if count_reached?(i)
            break if (@opts[:data] || @opts[:file]) && !@opts[:interval]
            sleep(@opts[:interval]) if @opts[:interval]
          end
        end

        wait_for_loops(receiver, sender)
      end

      def router_loop(task)
        receiver = task.async do
          i = 0
          loop do
            parts = recv_msg_raw
            identity = parts.shift
            parts.shift if parts.first == ""
            parts = @fmt.decompress(parts)
            result = eval_expr([display_routing_id(identity), *parts])
            output(result)
            i += 1
            break if count_reached?(i)
          end
        end

        sender = task.async do
          i = 0
          loop do
            parts = read_next
            break unless parts
            sleep(@opts[:delay]) if @opts[:delay] && i == 0
            if @opts[:target]
              payload = @fmt.compress(parts)
              @sock.send([resolve_target(@opts[:target]), "", *payload])
            else
              send_msg(parts)
            end
            i += 1
            break if count_reached?(i)
            break if (@opts[:data] || @opts[:file]) && !@opts[:interval]
            sleep(@opts[:interval]) if @opts[:interval]
          end
        end

        wait_for_loops(receiver, sender)
      end

      def server_reply_loop
        i = 0
        loop do
          parts = recv_msg_raw
          routing_id = parts.shift
          body = @fmt.decompress(parts)

          if @opts[:expr]
            reply = eval_expr(body)
            output([display_routing_id(routing_id), *(reply || [""])])
            @sock.send_to(routing_id, @fmt.compress(reply || [""]).first)
          elsif @opts[:echo]
            output([display_routing_id(routing_id), *body])
            @sock.send_to(routing_id, @fmt.compress(body).first || "")
          elsif @opts[:data] || @opts[:file] || !$stdin.tty?
            reply = read_next
            break unless reply
            output([display_routing_id(routing_id), *body])
            @sock.send_to(routing_id, @fmt.compress(reply).first || "")
          end
          i += 1
          break if count_reached?(i)
        end
      end

      def server_loop(task)
        receiver = task.async do
          i = 0
          loop do
            parts = recv_msg_raw
            routing_id = parts.shift
            parts = @fmt.decompress(parts)
            result = eval_expr([display_routing_id(routing_id), *parts])
            output(result)
            i += 1
            break if count_reached?(i)
          end
        end

        sender = task.async do
          i = 0
          loop do
            parts = read_next
            break unless parts
            sleep(@opts[:delay]) if @opts[:delay] && i == 0
            if @opts[:target]
              parts = @fmt.compress(parts)
              @sock.send_to(resolve_target(@opts[:target]), parts.first || "")
            else
              send_msg(parts)
            end
            i += 1
            break if count_reached?(i)
            break if (@opts[:data] || @opts[:file]) && !@opts[:interval]
            sleep(@opts[:interval]) if @opts[:interval]
          end
        end

        wait_for_loops(receiver, sender)
      end

      def wait_for_loops(receiver, sender)
        if @opts[:count] && @opts[:count] > 0
          receiver.wait
          sender.stop
        else
          sender.wait
          receiver.stop
        end
      end

      # ── Message I/O ────────────────────────────────────────────────

      def send_msg(parts)
        return if parts.empty?
        parts = @fmt.compress(parts)
        if @type_name == "radio"
          group = @opts[:group] || parts.shift
          @sock.publish(group, parts.first || "")
        else
          @sock.send(parts)
        end
        transient_ready!
      end

      def recv_msg
        parts = @fmt.decompress(@sock.receive)
        transient_ready!
        parts
      end

      def recv_msg_raw
        @sock.receive
      end

      def read_next
        if @opts[:data]
          @fmt.decode(@opts[:data] + "\n")
        elsif @opts[:file]
          @file_data ||= (@opts[:file] == "-" ? $stdin.read : File.read(@opts[:file])).chomp
          @fmt.decode(@file_data + "\n")
        elsif @opts[:format] == :msgpack
          @fmt.decode_msgpack($stdin)
        elsif @opts[:format] == :raw
          data = $stdin.read
          return nil if data.nil? || data.empty?
          [data]
        else
          line = $stdin.gets
          return nil if line.nil?
          @fmt.decode(line)
        end
      end

      def output(parts)
        return if @opts[:quiet]
        parts = [""] if parts.nil?
        $stdout.write(@fmt.encode(parts))
        $stdout.flush
      end

      # ── Routing helpers ────────────────────────────────────────────

      def display_routing_id(id)
        if id.bytes.all? { |b| b >= 0x20 && b <= 0x7E }
          id
        else
          "0x#{id.unpack1("H*")}"
        end
      end

      def resolve_target(target)
        if target.start_with?("0x")
          [target[2..].delete(" ")].pack("H*")
        else
          target
        end
      end

      # ── Eval / counting / logging ──────────────────────────────────

      def compile_expr
        return unless @opts[:expr]
        @eval_proc = eval("proc { #{@opts[:expr]} }")
      end

      def eval_expr(parts)
        return parts unless @eval_proc
        $F = parts
        result = @sock.instance_exec(&@eval_proc)
        case result
        when nil    then nil
        when Array  then result
        when String then [result]
        else             [result.to_s]
        end
      end

      def count_reached?(i)
        @opts[:count] && @opts[:count] > 0 && i >= @opts[:count]
      end

      def log(msg)
        $stderr.puts(msg)
      end
    end
  end
end
