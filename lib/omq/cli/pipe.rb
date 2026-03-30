# frozen_string_literal: true

module OMQ
  module CLI
    class PipeRunner
      attr_reader :config


      def initialize(config)
        @config = config
        @fmt    = Formatter.new(config.format, compress: config.compress)
      end


      def call(task)
        if config.parallel
          run_parallel
        else
          run_sequential(task)
        end
      end


      private


      def resolve_endpoints
        if config.in_endpoints.any?
          [config.in_endpoints, config.out_endpoints]
        else
          [[config.endpoints[0]], [config.endpoints[1]]]
        end
      end


      def attach_endpoints(sock, endpoints)
        endpoints.each { |ep| ep.bind? ? sock.bind(ep.url) : sock.connect(ep.url) }
      end


      def run_sequential(task)
        in_eps, out_eps = resolve_endpoints

        @pull = OMQ::PULL.new(linger: config.linger, recv_timeout: config.timeout)
        @push = OMQ::PUSH.new(linger: config.linger, send_timeout: config.timeout)
        @pull.reconnect_interval  = config.reconnect_ivl if config.reconnect_ivl
        @push.reconnect_interval  = config.reconnect_ivl if config.reconnect_ivl
        @pull.heartbeat_interval  = config.heartbeat_ivl if config.heartbeat_ivl
        @push.heartbeat_interval  = config.heartbeat_ivl if config.heartbeat_ivl

        attach_endpoints(@pull, in_eps)
        attach_endpoints(@push, out_eps)

        compile_expr
        @sock = @pull  # for eval instance_exec

        with_timeout(config.timeout) do
          @push.peer_connected.wait
          @pull.peer_connected.wait
        end

        if config.transient
          task.async do
            @pull.all_peers_gone.wait
            @pull.reconnect_enabled = false
            @pull.close_read
          end
        end

        @sock.instance_exec(&@recv_begin_proc) if @recv_begin_proc

        n = config.count
        i = 0
        loop do
          parts = @pull.receive
          break if parts.nil?
          parts = @fmt.decompress(parts)
          parts = eval_recv_expr(parts)
          if parts && !parts.empty?
            @push.send(@fmt.compress(parts))
          end
          i += 1
          break if n && n > 0 && i >= n
        end

        @sock.instance_exec(&@recv_end_proc) if @recv_end_proc
      ensure
        @pull&.close
        @push&.close
      end


      def run_parallel
        workers = config.parallel.times.map do
          Ractor.new(config) do |cfg|
            $VERBOSE = nil
            Console.logger = Console::Logger.new(Console::Output::Null.new)

            Sync do |task|
              # Parse BEGIN/END blocks and per-message expression
              begin_proc = end_proc = eval_proc = nil
              if cfg.recv_expr
                extract = ->(src, kw) {
                  s = src.index(/#{kw}\s*\{/)
                  return [src, nil] unless s
                  i = src.index("{", s); d = 1; j = i + 1
                  while j < src.length && d > 0
                    d += 1 if src[j] == "{"; d -= 1 if src[j] == "}"
                    j += 1
                  end
                  [src[0...s] + src[j..], src[(i + 1)..(j - 2)]]
                }
                expr, begin_body = extract.(cfg.recv_expr, "BEGIN")
                expr, end_body   = extract.(expr, "END")
                begin_proc = eval("proc { #{begin_body} }") if begin_body
                end_proc   = eval("proc { #{end_body} }")   if end_body
                if expr && !expr.strip.empty?
                  ractor_expr = expr.gsub(/\$F\b/, "__F")
                  eval_proc   = eval("proc { |__F| $_ = __F&.first; #{ractor_expr} }")
                end
              end

              formatter = OMQ::CLI::Formatter.new(cfg.format, compress: cfg.compress)

              pull = OMQ::PULL.new(linger: cfg.linger, recv_timeout: cfg.timeout)
              push = OMQ::PUSH.new(linger: cfg.linger, send_timeout: cfg.timeout)
              pull.reconnect_interval  = cfg.reconnect_ivl if cfg.reconnect_ivl
              push.reconnect_interval  = cfg.reconnect_ivl if cfg.reconnect_ivl
              pull.heartbeat_interval  = cfg.heartbeat_ivl if cfg.heartbeat_ivl
              push.heartbeat_interval  = cfg.heartbeat_ivl if cfg.heartbeat_ivl
              in_eps  = cfg.in_endpoints.any? ? cfg.in_endpoints : [cfg.endpoints[0]]
              out_eps = cfg.out_endpoints.any? ? cfg.out_endpoints : [cfg.endpoints[1]]
              in_eps.each  { |ep| pull.connect(ep.url) }
              out_eps.each { |ep| push.connect(ep.url) }

              if cfg.timeout
                task.with_timeout(cfg.timeout) do
                  push.peer_connected.wait
                  pull.peer_connected.wait
                end
              else
                push.peer_connected.wait
                pull.peer_connected.wait
              end

              if cfg.transient
                task.async do
                  pull.all_peers_gone.wait
                  pull.reconnect_enabled = false
                  pull.close_read
                end
              end

              begin_proc&.call

              i = 0
              loop do
                parts = pull.receive
                break if parts.nil?
                parts = formatter.decompress(parts)
                if eval_proc
                  result = eval_proc.call(parts)
                  parts = case result
                          when nil    then nil
                          when Array  then result
                          when String then [result]
                          else             [result.to_s]
                          end
                end
                if parts && !parts.empty?
                  push.send(formatter.compress(parts))
                end
                i += 1
                break if cfg.count && cfg.count > 0 && i >= cfg.count
              end

              end_proc&.call
            rescue Async::TimeoutError
              # exit cleanly on timeout
            ensure
              pull&.close
              push&.close
            end
          end
        end

        workers.each do |w|
          w.value
        rescue Ractor::RemoteError => e
          $stderr.puts "omq: Ractor error: #{e.cause&.message || e.message}"
        end
      end


      def with_timeout(seconds)
        if seconds
          Async::Task.current.with_timeout(seconds) { yield }
        else
          yield
        end
      end


      def compile_expr
        src = config.recv_expr
        return unless src
        expr, begin_body, end_body = extract_blocks(src)
        @recv_begin_proc = eval("proc { #{begin_body} }") if begin_body
        @recv_end_proc   = eval("proc { #{end_body} }")   if end_body
        @recv_eval_proc  = eval("proc { $_ = $F&.first; #{expr} }") if expr && !expr.strip.empty?
      end


      def extract_blocks(expr)
        begin_body = end_body = nil
        expr, begin_body = extract_block(expr, "BEGIN")
        expr, end_body   = extract_block(expr, "END")
        [expr, begin_body, end_body]
      end


      def extract_block(expr, keyword)
        start = expr.index(/#{keyword}\s*\{/)
        return [expr, nil] unless start

        i     = expr.index("{", start)
        depth = 1
        j     = i + 1
        while j < expr.length && depth > 0
          case expr[j]
          when "{" then depth += 1
          when "}" then depth -= 1
          end
          j += 1
        end

        body    = expr[(i + 1)..(j - 2)]
        trimmed = expr[0...start] + expr[j..]
        [trimmed, body]
      end


      def eval_recv_expr(parts)
        return parts unless @recv_eval_proc
        $F = parts
        result = @sock.instance_exec(&@recv_eval_proc)
        return nil if result.nil? || result.equal?(@sock)
        return [result] if config.format == :marshal
        case result
        when Array  then result
        when String then [result]
        else             [result.to_str]
        end
      rescue => e
        $stderr.puts "omq: eval error: #{e.message} (#{e.class})"
        exit 3
      end


      def log(msg)
        $stderr.puts(msg) if config.verbose
      end
    end
  end
end
