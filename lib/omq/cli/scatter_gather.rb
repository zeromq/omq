# frozen_string_literal: true

module OMQ
  module CLI
    class ScatterRunner < BaseRunner
      def run_loop(task) = run_send_logic
    end


    class GatherRunner < BaseRunner
      def run_loop(task) = run_recv_logic
    end
  end
end
