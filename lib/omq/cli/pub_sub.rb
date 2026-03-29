# frozen_string_literal: true

module OMQ
  module CLI
    class PubRunner < BaseRunner
      def run_loop(task) = run_send_logic
    end


    class SubRunner < BaseRunner
      def run_loop(task) = run_recv_logic
    end
  end
end
