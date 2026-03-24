# frozen_string_literal: true

require "async"

module OMQ
  module ZMTP
    # Shared IO reactor for the Ruby backend.
    #
    # When user code runs inside an Async reactor, pump tasks are spawned
    # as transient Async tasks directly. When no reactor is available
    # (e.g. bare Thread.new), a single shared IO thread hosts all pump
    # tasks — mirroring libzmq's IO thread architecture.
    #
    module Reactor
      @work_queue = Thread::Queue.new
      @thread     = nil
      @mutex      = Mutex.new
      @wake_r     = nil
      @wake_w     = nil

      class << self
        # Spawns a pump task (recv loop, send loop, accept loop).
        #
        # Inside an Async reactor: spawns as transient Async task.
        # Outside: dispatches to the shared IO thread.
        #
        # @return [#stop] a stoppable handle
        #
        def spawn_pump(&block)
          if Async::Task.current?
            Async(transient: true, &block)
          else
            handle = PumpHandle.new
            ensure_started
            @work_queue.push([:spawn, block, handle])
            @wake_w.write_nonblock(".") rescue nil
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
            @wake_w.write_nonblock(".") rescue nil
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
            @wake_r, @wake_w = IO.pipe
            ready = Thread::Queue.new
            @thread = Thread.new { run_reactor(ready, @wake_r) }
            @thread.name = "cztop-io"
            ready.pop
          end
        end

        # Stops the shared IO thread. Used in tests.
        #
        # @return [void]
        #
        def stop!
          @work_queue.push([:stop])
          @wake_w&.write_nonblock(".") rescue nil
          @thread&.join(2)
          @thread = nil
          @wake_r&.close rescue nil
          @wake_w&.close rescue nil
          @wake_r = nil
          @wake_w = nil
        end

        private

        def run_reactor(ready, wake_r)
          Async do |task|
            ready.push(true)
            loop do
              # Wait for wakeup signal (non-blocking for Async scheduler)
              wake_r.wait_readable
              wake_r.read_nonblock(256) rescue nil

              # Drain all pending work items
              while (item = @work_queue.pop(true) rescue nil)
                case item[0]
                when :spawn
                  _, block, handle = item
                  async_task = task.async(transient: true, &block)
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
end
