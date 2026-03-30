# frozen_string_literal: true

module OMQ
  module CLI
    class ReqRunner < BaseRunner
      private


      def run_loop(task)
        n = config.count
        i = 0
        sleep(config.delay) if config.delay
        if config.interval
          loop do
            parts = read_next
            break unless parts
            parts = eval_send_expr(parts)
            next unless parts
            send_msg(parts)
            reply = recv_msg
            break if reply.nil?
            reply = eval_recv_expr(reply)
            output(reply)
            i += 1
            break if n && n > 0 && i >= n
            interval = config.interval
            wait     = interval - (Time.now.to_f % interval)
            sleep(wait) if wait > 0
          end
        else
          loop do
            parts = read_next
            break unless parts
            parts = eval_send_expr(parts)
            next unless parts
            send_msg(parts)
            reply = recv_msg
            break if reply.nil?
            reply = eval_recv_expr(reply)
            output(reply)
            i += 1
            break if n && n > 0 && i >= n
            break if config.data || config.file
          end
        end
      end
    end


    class RepRunner < BaseRunner
      private


      def run_loop(task)
        n = config.count
        i = 0
        loop do
          msg = recv_msg
          break if msg.nil?
          if config.recv_expr || @recv_eval_proc
            reply = eval_recv_expr(msg)
            unless reply.equal?(SENT)
              output(reply)
              send_msg(reply || [""])
            end
          elsif config.echo
            output(msg)
            send_msg(msg)
          elsif config.data || config.file || !config.stdin_is_tty
            reply = read_next
            break unless reply
            output(msg)
            send_msg(reply)
          else
            abort "REP needs a reply source: --echo, --data, --file, -e, or stdin pipe"
          end
          i += 1
          break if n && n > 0 && i >= n
        end
      end
    end
  end
end
