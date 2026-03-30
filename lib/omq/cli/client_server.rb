# frozen_string_literal: true

module OMQ
  module CLI
    class ClientRunner < ReqRunner
    end


    class ServerRunner < BaseRunner
      private


      def run_loop(task)
        if config.echo || config.recv_expr || @recv_eval_proc || config.data || config.file || !config.stdin_is_tty
          reply_loop
        else
          monitor_loop(task)
        end
      end


      def reply_loop
        n = config.count
        i = 0
        loop do
          parts = recv_msg_raw
          break if parts.nil?
          routing_id = parts.shift
          body       = @fmt.decompress(parts)

          if config.recv_expr || @recv_eval_proc
            reply = eval_recv_expr(body)
            output([display_routing_id(routing_id), *(reply || [""])])
            @sock.send_to(routing_id, @fmt.compress(reply || [""]).first)
          elsif config.echo
            output([display_routing_id(routing_id), *body])
            @sock.send_to(routing_id, @fmt.compress(body).first || "")
          elsif config.data || config.file || !config.stdin_is_tty
            reply = read_next
            break unless reply
            output([display_routing_id(routing_id), *body])
            @sock.send_to(routing_id, @fmt.compress(reply).first || "")
          end
          i += 1
          break if n && n > 0 && i >= n
        end
      end


      def monitor_loop(task)
        receiver = task.async do
          n = config.count
          i = 0
          loop do
            parts = recv_msg_raw
            break if parts.nil?
            routing_id = parts.shift
            parts      = @fmt.decompress(parts)
            result = eval_recv_expr([display_routing_id(routing_id), *parts])
            output(result)
            i += 1
            break if n && n > 0 && i >= n
          end
        end

        sender = task.async do
          n = config.count
          i = 0
          sleep(config.delay) if config.delay
          if config.interval
            Async::Loop.quantized(interval: config.interval) do
              parts = read_next
              break unless parts
              send_targeted_or_eval(parts)
              i += 1
              break if n && n > 0 && i >= n
            end
          elsif config.data || config.file
            parts = read_next
            send_targeted_or_eval(parts) if parts
          else
            loop do
              parts = read_next
              break unless parts
              send_targeted_or_eval(parts)
              i += 1
              break if n && n > 0 && i >= n
            end
          end
        end

        wait_for_loops(receiver, sender)
      end


      def send_targeted_or_eval(parts)
        if @send_eval_proc
          parts = eval_send_expr(parts)
          return unless parts
          routing_id = resolve_target(parts.shift)
          @sock.send_to(routing_id, @fmt.compress(parts).first || "")
        elsif config.target
          parts = @fmt.compress(parts)
          @sock.send_to(resolve_target(config.target), parts.first || "")
        else
          send_msg(parts)
        end
      end
    end
  end
end
