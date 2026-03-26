# frozen_string_literal: true

module OMQ
  module ZMTP
    module Codec
      # ZMTP 3.1 greeting encode/decode.
      #
      # The greeting is always exactly 64 bytes:
      #   Offset  Bytes  Field
      #   0       1      0xFF (signature start)
      #   1-8     8      0x00 padding
      #   9       1      0x7F (signature end)
      #   10      1      major version
      #   11      1      minor version
      #   12-31   20     mechanism (null-padded ASCII)
      #   32      1      as-server flag (0x00 or 0x01)
      #   33-63   31     filler (0x00)
      #
      module Greeting
        SIZE             = 64
        SIGNATURE_START  = 0xFF
        SIGNATURE_END    = 0x7F
        VERSION_MAJOR    = 3
        VERSION_MINOR    = 1
        MECHANISM_OFFSET = 12
        MECHANISM_LENGTH = 20
        AS_SERVER_OFFSET = 32

        # Encodes a ZMTP 3.1 greeting.
        #
        # @param mechanism [String] security mechanism name (e.g. "NULL")
        # @param as_server [Boolean] whether this peer is the server
        # @return [String] 64-byte binary greeting
        #
        def self.encode(mechanism: "NULL", as_server: false)
          buf = "\xFF".b + ("\x00" * 8) + "\x7F".b
          buf << [VERSION_MAJOR, VERSION_MINOR].pack("CC")
          buf << mechanism.b.ljust(MECHANISM_LENGTH, "\x00")
          buf << (as_server ? "\x01" : "\x00")
          buf << ("\x00" * 31)
        end

        # Decodes a ZMTP greeting.
        #
        # @param data [String] 64-byte binary greeting
        # @return [Hash] { major:, minor:, mechanism:, as_server: }
        # @raise [ProtocolError] on invalid greeting
        #
        def self.decode(data)
          raise ProtocolError, "greeting too short (#{data.bytesize} bytes)" if data.bytesize < SIZE

          data = data.b

          unless data.getbyte(0) == SIGNATURE_START && data.getbyte(9) == SIGNATURE_END
            raise ProtocolError, "invalid greeting signature"
          end

          major = data.getbyte(10)
          minor = data.getbyte(11)

          unless major >= 3
            raise ProtocolError, "unsupported ZMTP version #{major}.#{minor} (need >= 3.0)"
          end

          mechanism = data.byteslice(MECHANISM_OFFSET, MECHANISM_LENGTH).delete("\x00")
          as_server = data.getbyte(AS_SERVER_OFFSET) == 1

          {
            major:     major,
            minor:     minor,
            mechanism: mechanism,
            as_server: as_server,
          }
        end
      end
    end
  end
end
