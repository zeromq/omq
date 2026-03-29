# frozen_string_literal: true

require "async"
require "async/queue"

module OMQ
  module ZMTP
    module Transport
      # In-process transport.
      #
      # Both peers are Ruby backend sockets in the same process (native
      # ZMQ's inproc registry is separate and unreachable). Messages are
      # transferred as Ruby arrays — no ZMTP framing, no byte
      # serialization. String parts are frozen by Writable#send to
      # prevent shared mutable state without copying.
      #
      module Inproc
        # Socket types that exchange commands (SUBSCRIBE/CANCEL) over inproc.
        #
        COMMAND_TYPES = %i[PUB SUB XPUB XSUB RADIO DISH].freeze

        # Global registry of bound inproc endpoints.
        #
        @registry = {}
        @mutex    = Mutex.new
        @waiters  = Hash.new { |h, k| h[k] = [] }


        class << self
          # Binds an engine to an inproc endpoint.
          #
          # @param endpoint [String] e.g. "inproc://my-endpoint"
          # @param engine [Engine] the owning engine
          # @return [Listener]
          # @raise [ArgumentError] if endpoint is already bound
          #
          def bind(endpoint, engine)
            @mutex.synchronize do
              raise ArgumentError, "endpoint already bound: #{endpoint}" if @registry.key?(endpoint)
              @registry[endpoint] = engine

              # Wake any pending connects
              @waiters[endpoint].each { |p| p.resolve(true) }
              @waiters.delete(endpoint)
            end
            Listener.new(endpoint)
          end


          # Connects to a bound inproc endpoint.
          #
          # @param endpoint [String] e.g. "inproc://my-endpoint"
          # @param engine [Engine] the connecting engine
          # @return [void]
          #
          def connect(endpoint, engine)
            bound_engine = @mutex.synchronize { @registry[endpoint] }

            unless bound_engine
              # Endpoint not bound yet. Wait with timeout derived from
              # reconnect_interval. If it doesn't appear, silently return —
              # matching ZMQ 4.x behavior where inproc connect to an
              # unbound endpoint succeeds but messages go nowhere.
              # A background task retries periodically.
              ri      = engine.options.reconnect_interval
              timeout = ri.is_a?(Range) ? ri.begin : ri
              promise = Async::Promise.new
              @mutex.synchronize { @waiters[endpoint] << promise }
              unless promise.wait?(timeout: timeout)
                @mutex.synchronize { @waiters[endpoint].delete(promise) }
                start_connect_retry(endpoint, engine)
                return
              end
              bound_engine = @mutex.synchronize { @registry[endpoint] }
            end

            establish_link(engine, bound_engine, endpoint)
          end


          # Removes a bound endpoint from the registry.
          #
          # @param endpoint [String]
          # @return [void]
          #
          def unbind(endpoint)
            @mutex.synchronize { @registry.delete(endpoint) }
          end


          # Resets the registry. Used in tests.
          #
          # @return [void]
          #
          def reset!
            @mutex.synchronize do
              @registry.clear
              @waiters.clear
            end
          end


          private


          # Wires up a client-server inproc pipe pair after validating
          # that the two socket types are compatible.
          #
          # @param client_engine [Engine] the connecting engine
          # @param server_engine [Engine] the bound engine
          # @param endpoint [String] the inproc endpoint name
          #
          def establish_link(client_engine, server_engine, endpoint)
            client_type = client_engine.socket_type
            server_type = server_engine.socket_type

            unless ZMTP::VALID_PEERS[client_type]&.include?(server_type)
              raise ProtocolError,
                    "incompatible socket types: #{client_type} cannot connect to #{server_type}"
            end

            # Only PUB/SUB-family types exchange commands (SUBSCRIBE/CANCEL)
            # over inproc. All other types use only the direct recv queue
            # bypass for data, so no internal queues are needed.
            needs_commands = COMMAND_TYPES.include?(client_type) ||
                             COMMAND_TYPES.include?(server_type)

            if needs_commands
              a_to_b = Async::Queue.new
              b_to_a = Async::Queue.new
            end

            client_pipe = DirectPipe.new(
              send_queue:    needs_commands ? a_to_b : nil,
              receive_queue: needs_commands ? b_to_a : nil,
              peer_identity: server_engine.options.identity,
              peer_type:     server_type.to_s,
            )
            server_pipe = DirectPipe.new(
              send_queue:    needs_commands ? b_to_a : nil,
              receive_queue: needs_commands ? a_to_b : nil,
              peer_identity: client_engine.options.identity,
              peer_type:     client_type.to_s,
            )

            client_pipe.peer = server_pipe
            server_pipe.peer = client_pipe

            client_engine.connection_ready(client_pipe, endpoint: endpoint)
            server_engine.connection_ready(server_pipe, endpoint: endpoint)
          end


          # Spawns a background task that periodically retries
          # #establish_link until the endpoint appears in the registry.
          #
          # @param endpoint [String] the inproc endpoint name
          # @param engine [Engine] the connecting engine
          #
          def start_connect_retry(endpoint, engine)
            Reactor.spawn_pump(annotation: "reconnect") do
              ri  = engine.options.reconnect_interval
              ivl = ri.is_a?(Range) ? ri.begin : ri
              loop do
                sleep ivl
                bound_engine = @mutex.synchronize { @registry[endpoint] }
                if bound_engine
                  establish_link(engine, bound_engine, endpoint)
                  break
                end
              end
            end
          end
        end

        # A bound inproc endpoint handle.
        #
        class Listener
          # @return [String] the bound endpoint
          #
          attr_reader :endpoint


          # @param endpoint [String]
          #
          def initialize(endpoint)
            @endpoint = endpoint
          end


          # Stops the listener by removing it from the registry.
          #
          # @return [void]
          #
          def stop
            Inproc.unbind(@endpoint)
          end
        end

        # A direct in-process pipe that transfers Ruby arrays through queues.
        #
        # Implements the same interface as Connection so routing strategies
        # can use it transparently.
        #
        # When a routing strategy sets {#direct_recv_queue} on a pipe,
        # {#send_message} enqueues directly into the peer's recv queue,
        # bypassing the intermediate pipe queues and the recv pump task.
        # This reduces inproc from 3 queue hops to 2 (send_queue →
        # recv_queue), eliminating the internal pipe queue in between.
        #
        class DirectPipe
          # @return [String] peer's socket type
          #
          attr_reader :peer_socket_type


          # @return [String] peer's identity
          #
          attr_reader :peer_identity


          # @return [DirectPipe, nil] the other end of this pipe pair
          #
          attr_accessor :peer


          # @return [Async::LimitedQueue, nil] when set, {#send_message}
          #   enqueues directly here instead of using the internal queue
          #
          attr_reader :direct_recv_queue


          # @return [Proc, nil] optional transform applied before
          #   enqueuing into {#direct_recv_queue}
          #
          attr_accessor :direct_recv_transform


          # @param send_queue [Async::Queue, nil] outgoing command queue
          #   (nil for non-PUB/SUB types that don't exchange commands)
          # @param receive_queue [Async::Queue, nil] incoming command queue
          # @param peer_identity [String]
          # @param peer_type [String]
          #
          def initialize(send_queue: nil, receive_queue: nil, peer_identity:, peer_type:)
            @send_queue            = send_queue
            @receive_queue         = receive_queue
            @peer_identity         = peer_identity || "".b
            @peer_socket_type      = peer_type
            @closed                = false
            @peer                  = nil
            @direct_recv_queue     = nil
            @direct_recv_transform = nil
            @pending_direct        = nil
          end


          # Sets the direct recv queue. Drains any messages that were
          # buffered before the queue was available.
          #
          def direct_recv_queue=(queue)
            @direct_recv_queue = queue
            if queue && @pending_direct
              @pending_direct.each do |msg|
                queue.enqueue(msg)
              end
              @pending_direct = nil
            end
          end


          # Sends a multi-frame message.
          #
          # When {#direct_recv_queue} is set (inproc fast path), the
          # message is delivered directly to the peer's recv queue,
          # skipping the internal pipe queues and the recv pump.
          #
          # @param parts [Array<String>]
          # @return [void]
          #
          def send_message(parts)
            raise IOError, "closed" if @closed
            if @direct_recv_queue
              msg = @direct_recv_transform ? @direct_recv_transform.call(parts) : parts
              @direct_recv_queue.enqueue(msg)
            elsif @send_queue
              @send_queue.enqueue(parts)
            else
              msg = @direct_recv_transform ? @direct_recv_transform.call(parts) : parts
              (@pending_direct ||= []) << msg
            end
          end


          alias write_message send_message


          # No-op — inproc has no IO buffer to flush.
          #
          # @return [void]
          #
          def flush = nil


          # Receives a multi-frame message.
          #
          # @return [Array<String>]
          # @raise [EOFError] if closed
          #
          def receive_message
            msg = @receive_queue.dequeue
            raise EOFError, "connection closed" if msg.nil?
            msg
          end


          # Sends a command via the internal command queue.
          # Only available for PUB/SUB-family pipes.
          #
          # @param command [Codec::Command]
          # @return [void]
          #
          def send_command(command)
            raise IOError, "closed" if @closed
            @send_queue.enqueue([:command, command])
          end


          # Reads one command frame from the internal command queue.
          # Used by PUB/XPUB subscription listeners.
          #
          # @return [Codec::Frame]
          #
          def read_frame
            loop do
              item = @receive_queue.dequeue
              raise EOFError, "connection closed" if item.nil?
              if item.is_a?(Array) && item.first == :command
                cmd = item[1]
                return Codec::Frame.new(cmd.to_body, command: true)
              end
            end
          end


          # Closes this pipe end.
          #
          # @return [void]
          #
          def close
            return if @closed
            @closed = true
            @send_queue&.enqueue(nil) # close sentinel
          end
        end
      end
    end
  end
end
