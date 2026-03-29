# frozen_string_literal: true

module OMQ
  module CLI
    class PushRunner < BaseRunner
      def run_loop(task) = run_send_logic
    end


    class PullRunner < BaseRunner
      def run_loop(task) = run_recv_logic
    end
  end
end
