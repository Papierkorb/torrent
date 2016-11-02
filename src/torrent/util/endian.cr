module Torrent
  module Util

    # Fast integer endian conversions
    module Endian
      extend self

      # Transforms the value from host byte order to network byte order
      def to_network(value)
        {% if IO::ByteFormat::SystemEndian != IO::ByteFormat::NetworkEndian %}
          swap(value)
        {% else %}
          value
        {% end %}
      end

      # Transforms the value from network byte order to host byte order
      def to_host(value)
        {% if IO::ByteFormat::SystemEndian != IO::ByteFormat::NetworkEndian %}
          swap(value)
        {% else %}
          value
        {% end %}
      end

      # Reverses the byte-sequence in *val*
      def swap(val : UInt8 | Int8)
        val
      end

      # ditto
      def swap(val : UInt16)
        (val >> 8) | (val << 8)
      end

      # ditto
      def swap(val : UInt32)
        ((val & 0xFFu32) << 24) | \
        ((val & 0xFF00u32) << 8) | \
        ((val & 0xFF0000u32) >> 8) | \
        ((val & 0xFF000000u32) >> 24)
      end

      # ditto
      def swap(val : UInt64)
        ((val & 0xFFu64) << 56) | \
        ((val & 0xFF00u64) << 40) | \
        ((val & 0xFF0000u64) << 24) | \
        ((val & 0xFF000000u64) << 8) | \
        ((val & 0xFF00000000u64) >> 8) | \
        ((val & 0xFF0000000000u64) >> 24) | \
        ((val & 0xFF000000000000u64) >> 40) | \
        ((val & 0xFF00000000000000u64) >> 56)
      end

      # ditto
      def swap(val : Int16)
        swap(val.to_u16).to_i16
      end

      # ditto
      def swap(val : Int32)
        swap(val.to_u32).to_i32
      end

      # ditto
      def swap(val : Int64)
        swap(val.to_u64).to_i64
      end
    end
  end
end
