# frozen_string_literal: true

module OMQ
  module CLI
    class RadioRunner < BaseRunner
      def run_loop(task) = run_send_logic


      private


      def send_msg(parts)
        return if parts.empty?
        parts = [Marshal.dump(parts)] if config.format == :marshal
        parts = @fmt.compress(parts)
        group = config.group || parts.shift
        @sock.publish(group, parts.first || "")
        transient_ready!
      end
    end


    class DishRunner < BaseRunner
      def run_loop(task) = run_recv_logic
    end
  end
end
