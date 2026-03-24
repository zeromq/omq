# frozen_string_literal: true

module OMQ
  module ZMTP
    # Manages one ZMTP peer connection over any transport IO.
    #
    # Handles the ZMTP 3.1 greeting and NULL handshake, then provides
    # message send/receive and command send/receive on top of the framing
    # codec.
    #
    class Connection
      # @return [String] peer's socket type (from READY handshake)
      #
      attr_reader :peer_socket_type

      # @return [String] peer's identity (from READY handshake)
      #
      attr_reader :peer_identity

      # @return [Object] transport IO (#read, #write, #close)
      #
      attr_reader :io

      # @param io [#read, #write, #close] transport IO
      # @param socket_type [String] our socket type name (e.g. "REQ")
      # @param identity [String] our identity
      # @param as_server [Boolean] whether we are the server side
      # @param heartbeat_interval [Numeric, nil] heartbeat interval in seconds
      # @param heartbeat_ttl [Numeric, nil] TTL to send in PING
      # @param heartbeat_timeout [Numeric, nil] timeout for PONG
      # @param max_message_size [Integer, nil] max frame size in bytes, nil = unlimited
      #
      def initialize(io, socket_type:, identity: "", as_server: false,
                     heartbeat_interval: nil, heartbeat_ttl: nil, heartbeat_timeout: nil,
                     max_message_size: nil)
        @io                  = io
        @socket_type         = socket_type
        @identity            = identity
        @as_server           = as_server
        @peer_socket_type    = nil
        @peer_identity       = nil
        @mutex               = Mutex.new
        @heartbeat_interval  = heartbeat_interval
        @heartbeat_ttl       = heartbeat_ttl || heartbeat_interval
        @heartbeat_timeout   = heartbeat_timeout || heartbeat_interval
        @last_received_at    = nil
        @heartbeat_task      = nil
        @max_message_size    = max_message_size
      end

      # Performs the full ZMTP 3.1 NULL handshake.
      #
      # 1. Exchange greetings (64 bytes each way)
      # 2. Validate peer greeting (version, mechanism)
      # 3. Exchange READY commands (socket type + identity)
      # 4. Validate peer socket type compatibility
      #
      # @return [void]
      # @raise [ProtocolError] on handshake failure
      #
      def handshake!
        # Send our greeting
        @io.write(Codec::Greeting.encode(mechanism: "NULL", as_server: @as_server))

        # Read peer greeting
        greeting_data = read_exact(Codec::Greeting::SIZE)
        peer_greeting = Codec::Greeting.decode(greeting_data)

        unless peer_greeting[:mechanism] == "NULL"
          raise ProtocolError, "unsupported mechanism: #{peer_greeting[:mechanism]}"
        end

        # Send our READY command
        ready_cmd = Codec::Command.ready(socket_type: @socket_type, identity: @identity)
        send_frame(ready_cmd.to_frame)

        # Read peer READY command
        peer_frame = read_frame
        unless peer_frame.command?
          raise ProtocolError, "expected command frame, got data frame"
        end

        peer_cmd = Codec::Command.from_body(peer_frame.body)
        unless peer_cmd.name == "READY"
          raise ProtocolError, "expected READY command, got #{peer_cmd.name}"
        end

        props = peer_cmd.properties
        @peer_socket_type = props["Socket-Type"]
        @peer_identity = props["Identity"] || ""

        unless @peer_socket_type
          raise ProtocolError, "peer READY missing Socket-Type"
        end

        unless ZMTP::VALID_PEERS[@socket_type.to_sym]&.include?(@peer_socket_type.to_sym)
          raise ProtocolError,
                "incompatible socket types: #{@socket_type} cannot connect to #{@peer_socket_type}"
        end
      end

      # Sends a multi-frame message.
      #
      # @param parts [Array<String>] message frames
      # @return [void]
      #
      def send_message(parts)
        @mutex.synchronize do
          parts.each_with_index do |part, i|
            more = i < parts.size - 1
            @io.write(Codec::Frame.new(part, more: more).to_wire)
          end
        end
      end

      # Receives a multi-frame message.
      # PING/PONG commands are handled automatically by #read_frame.
      #
      # @return [Array<String>] message frames
      # @raise [EOFError] if connection is closed
      #
      def receive_message
        frames = []
        loop do
          frame = read_frame
          if frame.command?
            yield frame if block_given?
            next
          end
          frames << frame.body
          break unless frame.more?
        end
        frames
      end

      # Starts the heartbeat sender task. Call after handshake.
      #
      # @return [#stop, nil] the heartbeat task, or nil if disabled
      #
      def start_heartbeat
        return nil unless @heartbeat_interval
        @last_received_at = monotonic_now
        @heartbeat_task = Reactor.spawn_pump do
          loop do
            sleep @heartbeat_interval
            # Send PING with TTL
            send_command(Codec::Command.ping(
              ttl:     @heartbeat_ttl || 0,
              context: "".b,
            ))
            # Check if peer has gone silent
            if @heartbeat_timeout && @last_received_at
              elapsed = monotonic_now - @last_received_at
              if elapsed > @heartbeat_timeout
                close
                break
              end
            end
          end
        rescue IOError, EOFError
          # connection closed
        end
      end

      # Sends a command.
      #
      # @param command [Codec::Command]
      # @return [void]
      #
      def send_command(command)
        @mutex.synchronize { @io.write(command.to_frame.to_wire) }
      end

      # Reads one frame from the wire. Handles PING/PONG automatically.
      #
      # @return [Codec::Frame]
      # @raise [EOFError] if connection is closed
      #
      def read_frame
        loop do
          frame = Codec::Frame.read_from(@io)
          touch_heartbeat
          if @max_message_size && !frame.command? && frame.body.bytesize > @max_message_size
            close
            raise ProtocolError, "frame size #{frame.body.bytesize} exceeds max_message_size #{@max_message_size}"
          end
          if frame.command?
            cmd = Codec::Command.from_body(frame.body)
            case cmd.name
            when "PING"
              _, context = cmd.ping_ttl_and_context
              send_command(Codec::Command.pong(context: context))
              next
            when "PONG"
              next
            end
          end
          return frame
        end
      end

      # Closes the connection.
      #
      # @return [void]
      #
      def close
        @heartbeat_task&.stop rescue nil
        @io.close
      rescue IOError
        # already closed
      end

      private

      def touch_heartbeat
        @last_received_at = monotonic_now if @heartbeat_interval
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Sends one frame to the wire.
      #
      # @param frame [Codec::Frame]
      # @return [void]
      #
      def send_frame(frame)
        @mutex.synchronize { @io.write(frame.to_wire) }
      end

      # Reads exactly n bytes from @io.
      #
      # @param n [Integer]
      # @return [String]
      # @raise [EOFError]
      #
      def read_exact(n)
        data = "".b
        while data.bytesize < n
          chunk = @io.read(n - data.bytesize)
          raise EOFError, "connection closed" if chunk.nil? || chunk.empty?
          data << chunk
        end
        data
      end
    end
  end
end
