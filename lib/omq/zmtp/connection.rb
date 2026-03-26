# frozen_string_literal: true

module OMQ
  module ZMTP
    # Manages one ZMTP peer connection over any transport IO.
    #
    # Delegates the security handshake to a Mechanism object (Null, Curve, etc.),
    # then provides message send/receive and command send/receive on top of the
    # framing codec.
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
      # @param mechanism [Mechanism::Null, Mechanism::Curve] security mechanism
      # @param heartbeat_interval [Numeric, nil] heartbeat interval in seconds
      # @param heartbeat_ttl [Numeric, nil] TTL to send in PING
      # @param heartbeat_timeout [Numeric, nil] timeout for PONG
      # @param max_message_size [Integer, nil] max frame size in bytes, nil = unlimited
      #
      def initialize(io, socket_type:, identity: "", as_server: false,
                     mechanism: nil,
                     heartbeat_interval: nil, heartbeat_ttl: nil, heartbeat_timeout: nil,
                     max_message_size: nil)
        @io                  = io
        @socket_type         = socket_type
        @identity            = identity
        @as_server           = as_server
        @mechanism           = mechanism || Mechanism::Null.new
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

      # Performs the full ZMTP handshake via the configured mechanism.
      #
      # @return [void]
      # @raise [ProtocolError] on handshake failure
      #
      def handshake!
        result = @mechanism.handshake!(
          @io,
          as_server:   @as_server,
          socket_type: @socket_type,
          identity:    @identity,
        )

        @peer_socket_type = result[:peer_socket_type]
        @peer_identity    = result[:peer_identity]

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
            if @mechanism.encrypted?
              @io.write(@mechanism.encrypt(part.b, more: more))
            else
              @io.write(Codec::Frame.new(part, more: more).to_wire)
            end
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
        rescue *ZMTP::CONNECTION_LOST
          # connection closed
        end
      end

      # Sends a command.
      #
      # @param command [Codec::Command]
      # @return [void]
      #
      def send_command(command)
        @mutex.synchronize do
          if @mechanism.encrypted?
            @io.write(@mechanism.encrypt(command.to_body, command: true))
          else
            @io.write(command.to_frame.to_wire)
          end
        end
      end

      # Reads one frame from the wire. Handles PING/PONG automatically.
      # When using an encrypted mechanism, MESSAGE commands are decrypted
      # back to ZMTP frames transparently.
      #
      # @return [Codec::Frame]
      # @raise [EOFError] if connection is closed
      #
      def read_frame
        loop do
          frame = Codec::Frame.read_from(@io)
          touch_heartbeat

          # When CURVE is active, every wire frame is a MESSAGE envelope
          # (data frame with "\x07MESSAGE" prefix). Decrypt to recover the
          # inner ZMTP frame. This check only runs when encrypted? is true,
          # so user data frames are never misdetected.
          if @mechanism.encrypted? && frame.body.bytesize > 8 && frame.body.byteslice(0, 8) == "\x07MESSAGE".b
            frame = @mechanism.decrypt(frame)
          end

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

    end
  end
end
