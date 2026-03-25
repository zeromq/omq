# frozen_string_literal: true

module OMQ
  module ZMTP
    module Codec
      # ZMTP frame encode/decode.
      #
      # Wire format:
      #   Byte 0:   flags (bit 0=MORE, bit 1=LONG, bit 2=COMMAND)
      #   Next 1-8: size (1-byte if short, 8-byte big-endian if LONG)
      #   Next N:   body
      #
      class Frame
        FLAGS_MORE    = 0x01
        FLAGS_LONG    = 0x02
        FLAGS_COMMAND = 0x04

        # Short frame: 1-byte size, max body 255 bytes.
        #
        SHORT_MAX = 255

        # @return [String] frame body (binary)
        #
        attr_reader :body

        # @param body [String] frame body
        # @param more [Boolean] more frames follow
        # @param command [Boolean] this is a command frame
        #
        def initialize(body, more: false, command: false)
          @body    = body.b
          @more    = more
          @command = command
        end

        # @return [Boolean] true if more frames follow in this message
        #
        def more?    = @more

        # @return [Boolean] true if this is a command frame
        #
        def command? = @command

        # Encodes to wire bytes.
        #
        # @return [String] binary wire representation (flags + size + body)
        #
        def to_wire
          size = @body.bytesize
          flags = 0
          flags |= FLAGS_MORE if @more
          flags |= FLAGS_COMMAND if @command

          if size > SHORT_MAX
            flags |= FLAGS_LONG
            buf = IO::Buffer.new(9 + size)
            buf.set_value(:U8, 0, flags)
            buf.set_value(:U64, 1, size) # big-endian
            buf.set_string(@body, 9)
            buf.get_string(0, 9 + size, Encoding::BINARY)
          else
            buf = IO::Buffer.new(2 + size)
            buf.set_value(:U8, 0, flags)
            buf.set_value(:U8, 1, size)
            buf.set_string(@body, 2)
            buf.get_string(0, 2 + size, Encoding::BINARY)
          end
        end

        # Reads one frame from an IO-like object.
        #
        # @param io [#read] must support read(n) returning exactly n bytes
        # @return [Frame]
        # @raise [ProtocolError] on invalid frame
        # @raise [EOFError] if the connection is closed
        #
        def self.read_from(io)
          flags_byte = io.read_exactly(1)
          flags_buf = IO::Buffer.for(flags_byte)
          flags = flags_buf.get_value(:U8, 0)

          more = (flags & FLAGS_MORE) != 0
          long = (flags & FLAGS_LONG) != 0
          command = (flags & FLAGS_COMMAND) != 0

          if long
            size_bytes = io.read_exactly(8)
            size_buf = IO::Buffer.for(size_bytes)
            size = size_buf.get_value(:U64, 0) # big-endian
          else
            size_byte = io.read_exactly(1)
            size_buf = IO::Buffer.for(size_byte)
            size = size_buf.get_value(:U8, 0)
          end

          body = size > 0 ? io.read_exactly(size) : "".b

          new(body, more: more, command: command)
        end

      end
    end
  end
end
