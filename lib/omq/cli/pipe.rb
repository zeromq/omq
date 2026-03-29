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


      def run_sequential(task)
        pull_ep = config.endpoints[0]
        push_ep = config.endpoints[1]

        @pull = OMQ::PULL.new(linger: config.linger, recv_timeout: config.timeout)
        @push = OMQ::PUSH.new(linger: config.linger, send_timeout: config.timeout)

        pull_ep.bind? ? @pull.bind(pull_ep.url) : @pull.connect(pull_ep.url)
        push_ep.bind? ? @push.bind(push_ep.url) : @push.connect(push_ep.url)

        compile_expr
        @sock = @pull  # for eval_expr instance_exec

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

        n = config.count
        i = 0
        loop do
          parts = @pull.receive
          break if parts.nil?
          parts = @fmt.decompress(parts)
          parts = eval_expr(parts)
          if parts && !parts.empty?
            @push.send(@fmt.compress(parts))
          end
          i += 1
          break if n && n > 0 && i >= n
        end
      ensure
        @pull&.close
        @push&.close
      end


      def run_parallel
        pull_url  = config.endpoints[0].url
        push_url  = config.endpoints[1].url
        expr      = config.expr
        fmt_name  = config.format
        compress  = config.compress
        linger    = config.linger
        timeout   = config.timeout
        transient = config.transient
        count     = config.count

        workers = config.parallel.times.map do
          Ractor.new(pull_url, push_url, expr, fmt_name, compress, linger, timeout, transient, count) do
            |purl, surl, xpr, fmt, comp, ling, tout, trans, cnt|

            $VERBOSE = nil
            Console.logger = Console::Logger.new(Console::Output::Null.new)

            Sync do |task|
              # Compile eval — rewrite $F to __F (proc parameter)
              eval_proc = if xpr
                           ractor_expr = xpr.gsub(/\$F\b/, "__F")
                           eval("proc { |__F| $_ = __F&.first; #{ractor_expr} }")
                         end

              formatter = OMQ::CLI::Formatter.new(fmt, compress: comp)

              pull = OMQ::PULL.new(linger: ling, recv_timeout: tout)
              push = OMQ::PUSH.new(linger: ling, send_timeout: tout)
              pull.connect(purl)
              push.connect(surl)

              if tout
                task.with_timeout(tout) do
                  push.peer_connected.wait
                  pull.peer_connected.wait
                end
              else
                push.peer_connected.wait
                pull.peer_connected.wait
              end

              if trans
                task.async do
                  pull.all_peers_gone.wait
                  pull.reconnect_enabled = false
                  pull.close_read
                end
              end

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
                break if cnt && cnt > 0 && i >= cnt
              end
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
        return unless config.expr
        @eval_proc = eval("proc { $_ = $F&.first; #{config.expr} }")
      end


      def eval_expr(parts)
        return parts unless @eval_proc
        $F = parts
        result = @sock.instance_exec(&@eval_proc)
        return nil if result.nil?
        return [result] if config.format == :marshal
        case result
        when Array  then result
        when String then [result]
        else             [result.to_str]
        end
      rescue => e
        $stderr.puts "omq: -e error: #{e.message} (#{e.class})"
        Process.exit!(3)
      end


      def log(msg)
        $stderr.puts(msg) if config.verbose
      end
    end
  end
end
