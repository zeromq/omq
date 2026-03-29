# frozen_string_literal: true

module OMQ
  module CLI
    # Handles encoding/decoding messages in the configured format,
    # plus optional Zstandard compression.
    class Formatter
      def initialize(format, compress: false)
        @format   = format
        @compress = compress
      end


      def encode(parts)
        case @format
        when :ascii
          parts.map { |p| p.b.gsub(/[^[:print:]\t]/, ".") }.join("\t") + "\n"
        when :quoted
          parts.map { |p| p.b.dump[1..-2] }.join("\t") + "\n"
        when :raw
          parts.each_with_index.map do |p, i|
            ZMTP::Codec::Frame.new(p.to_s, more: i < parts.size - 1).to_wire
          end.join
        when :jsonl
          JSON.generate(parts) + "\n"
        when :msgpack
          MessagePack.pack(parts)
        when :marshal
          parts.map(&:inspect).join("\t") + "\n"
        end
      end


      def decode(line)
        case @format
        when :ascii, :marshal
          line.chomp.split("\t")
        when :quoted
          line.chomp.split("\t").map { |p| "\"#{p}\"".undump }
        when :raw
          [line]
        when :jsonl
          arr = JSON.parse(line.chomp)
          abort "JSON Lines input must be an array of strings" unless arr.is_a?(Array) && arr.all? { |e| e.is_a?(String) }
          arr
        end
      end


      def decode_marshal(io)
        Marshal.load(io)
      rescue EOFError, TypeError
        nil
      end


      def decode_msgpack(io)
        @msgpack_unpacker ||= MessagePack::Unpacker.new(io)
        @msgpack_unpacker.read
      rescue EOFError
        nil
      end


      def compress(parts)
        @compress ? parts.map { |p| Zstd.compress(p) } : parts
      end


      def decompress(parts)
        @compress ? parts.map { |p| Zstd.decompress(p) } : parts
      end
    end
  end
end
