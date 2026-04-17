# frozen_string_literal: true

require "async/loop"

module OMQ
  class Engine
    # Spawns a periodic maintenance task for the parent mechanism.
    #
    # The mechanism declares maintenance needs via +#maintenance+,
    # which returns +{ interval:, task: }+ or nil.
    #
    module Maintenance
      # @param parent_task [Async::Task]
      # @param mechanism [#maintenance, nil]
      #
      def self.start(parent_task, mechanism)
        return unless mechanism.respond_to?(:maintenance)
        spec = mechanism.maintenance or return spec

        interval = spec[:interval]
        callable = spec[:task]

        parent_task.async(transient: true, annotation: "mechanism maintenance") do
          Async::Loop.quantized(interval: interval) do
            callable.call
          end
        rescue Async::Stop
          # clean shutdown
        end
      end

    end
  end
end
