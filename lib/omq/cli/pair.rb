# frozen_string_literal: true

module OMQ
  module CLI
    class PairRunner < BaseRunner
      private


      def run_loop(task)
        receiver = task.async do
          n = config.count
          i = 0
          loop do
            parts = recv_msg
            break if parts.nil?
            parts = eval_recv_expr(parts)
            output(parts)
            i += 1
            break if n && n > 0 && i >= n
          end
        end

        sender = task.async do
          run_send_logic
        end

        wait_for_loops(receiver, sender)
      end
    end
  end
end
