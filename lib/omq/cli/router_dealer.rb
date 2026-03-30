# frozen_string_literal: true

module OMQ
  module CLI
    class DealerRunner < PairRunner
    end


    class RouterRunner < BaseRunner
      private


      def run_loop(task)
        receiver = task.async do
          n = config.count
          i = 0
          loop do
            parts = recv_msg_raw
            break if parts.nil?
            identity = parts.shift
            parts.shift if parts.first == ""
            parts = @fmt.decompress(parts)
            result = eval_recv_expr([display_routing_id(identity), *parts])
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
          identity = resolve_target(parts.shift)
          payload  = @fmt.compress(parts)
          @sock.send([identity, "", *payload])
        elsif config.target
          payload = @fmt.compress(parts)
          @sock.send([resolve_target(config.target), "", *payload])
        else
          send_msg(parts)
        end
      end
    end
  end
end
