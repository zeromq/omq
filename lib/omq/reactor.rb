# frozen_string_literal: true

require "async"

module OMQ
  # Shared IO reactor for the Ruby backend.
  #
  # When user code runs inside an Async reactor, pump tasks are spawned
  # as transient Async tasks directly. When no reactor is available
  # (e.g. bare Thread.new), a single shared IO thread hosts all pump
  # tasks — mirroring libzmq's IO thread architecture.
  #
  module Reactor
    @work_queue = Async::Queue.new
    @thread     = nil
    @mutex      = Mutex.new

    class << self
      # Spawns a pump task (recv loop, send loop, accept loop).
      #
      # Inside an Async reactor: spawns as transient Async task.
      # Outside: dispatches to the shared IO thread.
      #
      # @return [#stop] a stoppable handle
      #
      def spawn_pump(annotation: nil, &block)
        if Async::Task.current?
          Async(transient: true, annotation: annotation, &block)
        else
          handle = PumpHandle.new
          ensure_started
          @work_queue.push([:spawn, block, handle, annotation])
          handle
        end
      end

      # Runs a block synchronously within an Async context.
      #
      # Inside an Async reactor: runs directly.
      # Outside: dispatches to the shared IO thread and waits.
      #
      # @return [Object] the block's return value
      #
      def run(&block)
        if Async::Task.current?
          yield
        else
          result_queue = Thread::Queue.new
          ensure_started
          @work_queue.push([:run, block, result_queue])
          status, value = result_queue.pop
          raise value if status == :error
          value
        end
      end

      # Ensures the shared IO thread is running.
      #
      # @return [void]
      #
      def ensure_started
        @mutex.synchronize do
          return if @thread&.alive?
          ready = Thread::Queue.new
          @thread = Thread.new { run_reactor(ready) }
          @thread.name = "omq-io"
          ready.pop
        end
      end

      # Stops the shared IO thread. Used in tests.
      #
      # @return [void]
      #
      def stop!
        @work_queue.push([:stop])
        @thread&.join(2)
        @thread = nil
      end

      private

      # Runs the shared Async reactor loop, dispatching work items.
      #
      # @param ready [Thread::Queue] signaled once the reactor is accepting work
      #
      def run_reactor(ready)
        Async do |task|
          ready.push(true)
          loop do
            item = @work_queue.dequeue
            case item[0]
            when :spawn
              _, block, handle, annotation = item
              async_task = task.async(transient: true, annotation: annotation, &block)
              handle.task = async_task
            when :run
              _, block, result_queue = item
              task.async do
                result_queue.push([:ok, block.call])
              rescue => e
                result_queue.push([:error, e])
              end
            when :stop
              return
            end
          end
        end
      end
    end

    # A stoppable handle for a pump task running in the shared reactor.
    #
    class PumpHandle
      # @return [Async::Task, nil]
      #
      attr_accessor :task


      # Stops the pump task.
      #
      # @return [void]
      #
      def stop
        @task&.stop
      end
    end
  end
end
