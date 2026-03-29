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
        pull_ep = config.endpoints[0]
        push_ep = config.endpoints[1]

        @pull = OMQ::PULL.new(nil, linger: config.linger)
        @push = OMQ::PUSH.new(nil, linger: config.linger)
        @pull.recv_timeout = config.timeout if config.timeout
        @push.send_timeout = config.timeout if config.timeout

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


      private


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
