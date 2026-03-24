# frozen_string_literal: true

module OMQ
  module ZMTP
    module Codec
      # ZMTP command encode/decode.
      #
      # Command frame body format:
      #   1 byte:    command name length
      #   N bytes:   command name
      #   remaining: command data
      #
      # READY command data = property list:
      #   1 byte:  property name length
      #   N bytes: property name
      #   4 bytes: property value length (big-endian)
      #   N bytes: property value
      #
      class Command
        # @return [String] command name (e.g. "READY", "SUBSCRIBE")
        #
        attr_reader :name

        # @return [String] command data (binary)
        #
        attr_reader :data

        # @param name [String] command name
        # @param data [String] command data
        #
        def initialize(name, data = "".b)
          @name = name
          @data = data.b
        end

        # Encodes as a command frame body.
        #
        # @return [String] binary body (name-length + name + data)
        #
        def to_body
          name_bytes = @name.b
          buf = IO::Buffer.new(1 + name_bytes.bytesize + @data.bytesize)
          buf.set_value(:U8, 0, name_bytes.bytesize)
          buf.set_string(name_bytes, 1)
          buf.set_string(@data, 1 + name_bytes.bytesize)
          buf.get_string(0, buf.size, Encoding::BINARY)
        end

        # Encodes as a complete command Frame.
        #
        # @return [Frame]
        #
        def to_frame
          Frame.new(to_body, command: true)
        end

        # Decodes a command from a frame body.
        #
        # @param body [String] binary frame body
        # @return [Command]
        # @raise [ProtocolError] on malformed command
        #
        def self.from_body(body)
          body = body.b
          raise ProtocolError, "command body too short" if body.bytesize < 1

          buf = IO::Buffer.for(body)
          name_len = buf.get_value(:U8, 0)

          raise ProtocolError, "command name truncated" if body.bytesize < 1 + name_len

          name = buf.get_string(1, name_len, Encoding::BINARY)
          data = body.byteslice(1 + name_len..)
          new(name, data)
        end

        # Builds a READY command with Socket-Type and Identity properties.
        #
        # @param socket_type [String] e.g. "REQ", "REP", "PAIR"
        # @param identity [String] peer identity (can be empty)
        # @return [Command]
        #
        def self.ready(socket_type:, identity: "")
          props = encode_properties(
            "Socket-Type" => socket_type,
            "Identity"    => identity,
          )
          new("READY", props)
        end

        # Builds a SUBSCRIBE command.
        #
        # @param prefix [String] subscription prefix
        # @return [Command]
        #
        def self.subscribe(prefix)
          new("SUBSCRIBE", prefix.b)
        end

        # Builds a CANCEL command (unsubscribe).
        #
        # @param prefix [String] subscription prefix to cancel
        # @return [Command]
        #
        def self.cancel(prefix)
          new("CANCEL", prefix.b)
        end

        # Builds a PING command.
        #
        # @param ttl [Numeric] time-to-live in seconds (sent as deciseconds)
        # @param context [String] optional context bytes (up to 16 bytes)
        # @return [Command]
        #
        def self.ping(ttl: 0, context: "".b)
          # TTL is encoded as 2-byte big-endian value in tenths of a second
          ttl_ds = (ttl * 10).to_i
          buf = IO::Buffer.new(2 + context.bytesize)
          buf.set_value(:U16, 0, ttl_ds)
          buf.set_string(context.b, 2) if context.bytesize > 0
          new("PING", buf.get_string(0, buf.size, Encoding::BINARY))
        end

        # Builds a PONG command.
        #
        # @param context [String] context bytes from the PING
        # @return [Command]
        #
        def self.pong(context: "".b)
          new("PONG", context.b)
        end

        # Extracts TTL (in seconds) and context from a PING command's data.
        #
        # @return [Array(Numeric, String)] [ttl_seconds, context_bytes]
        #
        def ping_ttl_and_context
          buf = IO::Buffer.for(@data)
          ttl_ds = buf.get_value(:U16, 0)
          context = @data.bytesize > 2 ? @data.byteslice(2..) : "".b
          [ttl_ds / 10.0, context]
        end

        # Parses READY command data as a property list.
        #
        # @return [Hash<String, String>] property name => value
        # @raise [ProtocolError] on malformed properties
        #
        def properties
          result = {}
          buf = IO::Buffer.for(@data)
          offset = 0

          while offset < @data.bytesize
            raise ProtocolError, "property name truncated" if offset + 1 > @data.bytesize
            name_len = buf.get_value(:U8, offset)
            offset += 1

            raise ProtocolError, "property name truncated" if offset + name_len > @data.bytesize
            name = buf.get_string(offset, name_len, Encoding::BINARY)
            offset += name_len

            raise ProtocolError, "property value length truncated" if offset + 4 > @data.bytesize
            value_len = buf.get_value(:U32, offset) # big-endian
            offset += 4

            raise ProtocolError, "property value truncated" if offset + value_len > @data.bytesize
            value = buf.get_string(offset, value_len, Encoding::BINARY)
            offset += value_len

            result[name] = value
          end

          result
        end

        # Encodes a hash of properties into ZMTP property list format.
        #
        # @param props [Hash<String, String>]
        # @return [String] binary property list
        #
        def self.encode_properties(props)
          parts = props.map do |name, value|
            name_bytes = name.b
            value_bytes = value.b
            buf = IO::Buffer.new(1 + name_bytes.bytesize + 4 + value_bytes.bytesize)
            buf.set_value(:U8, 0, name_bytes.bytesize)
            buf.set_string(name_bytes, 1)
            buf.set_value(:U32, 1 + name_bytes.bytesize, value_bytes.bytesize) # big-endian
            buf.set_string(value_bytes, 1 + name_bytes.bytesize + 4)
            buf.get_string(0, buf.size, Encoding::BINARY)
          end
          parts.join
        end
        private_class_method :encode_properties
      end
    end
  end
end
