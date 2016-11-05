module Torrent
  module Util

    # Wraps a `Bytes` so we can work with it as bitfield in terms of BitTorrent.
    struct Bitfield
      include Enumerable(Bool)
      BITS_PER_BYTE = 8u64

      # The inner data
      getter data : Bytes

      # The bit count in the bitfield
      getter size : Int32

      def initialize(bit_size : Int32, byte : UInt8? = 0u8)
        @size = bit_size
        @data = Bytes.new(Bitfield.bytesize(bit_size), byte)
      end

      def initialize(data : Bytes, size : Int32? = nil)
        @data = data
        @size = size || (data.size * 8)

        raise ArgumentError.new("size must be <= data.size * 8") unless @size <= data.size * BITS_PER_BYTE
      end

      # Restores a bitfield from a hexstring, as built by `Slice#hexstring`.
      #
      # **Warning**: The *hexstring* must be a string containing only lower-case
      # hexdigits.
      def self.restore(bit_size : Int32, hexstring : String)
        "0123456789abcdef"
        bytes = hexstring.to_slice
        if bytes.size != bytesize(bit_size) * 2
          raise ArgumentError.new("Wrong hexstring length for bit count")
        end

        data = Bytes.new(bytes.size / 2) do |idx|
          from_hex(bytes[idx * 2]) << 4 | from_hex(bytes[idx * 2 + 1])
        end

        new(data, bit_size)
      end

      # Mirrors `Slice#to_hex`
      private def self.from_hex(c : UInt8) : UInt8
        (c < 0x61) ? c - 0x30 : c - 0x61 + 10
      end

      # Returns the count of bytes needed to house a bitfield of *bit_count*
      # bits.
      def self.bytesize(bit_count)
        bytes = bit_count / BITS_PER_BYTE
        bytes += 1 unless bit_count.divisible_by? BITS_PER_BYTE
        bytes
      end

      def each
        @size.times do |idx|
          yield self[idx]
        end
      end

      def each(value : Bool)
        @size.times do |idx|
          yield idx if self[idx] == value
        end
      end

      def count(value : Bool)
        count = 0
        data, trailing, _trailing_off = uint64_slice

        data.each{|el| count += el.popcount}
        trailing.each{|el| count += el.popcount}

        value ? count : @size - count
      end

      # Returns the bitfield bytes
      def to_bytes
        @data
      end

      # Deep-copies the bitfield
      def clone
        copy = Bytes.new(@data.size)
        copy.copy_from(@data)
        Bitfield.new(copy, @size)
      end

      delegate bytesize, to: @data

      # Returns true if every bit is set in the bitfield
      def all_ones?
        all?(true)
      end

      # Returns true if no bit is set in the bitfield
      def all_zero?
        all?(false)
      end

      # Returns true if all bits are equal to *bit_value*
      def all?(bit_value : Bool)
        big_value = bit_value ? UInt64::MAX : UInt64::MIN
        small_value = bit_value ? UInt8::MAX : UInt8::MIN
        data, trailing, _trailing_off = uint64_slice

        found = data.find{|el| el != big_value}
        return false if found

        if trailing.size > 0
          all_trailing(trailing, small_value)
        else
          true
        end
      end

      private def all_trailing(trailing, small_value)
        found = trailing[0, trailing.size - 1].find{|el| el != small_value}
        return false if found

        remaining = @size % 8
        if remaining == 0
          (trailing[-1] == small_value)
        else
          mask = ~(UInt8::MAX >> remaining)
          (trailing[-1] & mask) == mask
        end
      end

      # Returns the bit at *index*
      def [](index : Int) : Bool
        byte, bit = bit_index(index)
        (@data[byte] & (1 << bit)) != 0
      end

      # Sets the bit at *index* to *value*
      def []=(index : Int, value : Bool) : Bool
        byte, bit = bit_index(index)
        mask = 1 << bit

        if value
          @data[byte] |= mask
        else
          @data[byte] &= ~mask
        end

        value
      end

      private def bit_index(index : Int)
        byte, bit = index.divmod BITS_PER_BYTE

        { byte, BITS_PER_BYTE - bit - 1 }
      end

      # Finds the index of the next bit, from the beginning, which is not set.
      # If no bit is unset, returns `nil`.
      def find_next_unset
        data, trailing, trailing_off = uint64_slice
        found = find_index(data){|el| el != UInt64::MAX }

        if found
          (found * 64) + find_next_unset_bit(data[found], 64u64)
        else
          found8 = find_next_slow(trailing)
          (data.size * 64) + found8 if found8
        end
      end

      private def find_next_slow(trailing)
        found = find_index(trailing){|el| el != UInt8::MAX }

        if found
          (found * 8) + find_next_unset_bit(trailing[found].to_u64, 8u64)
        end
      end

      @[AlwaysInline]
      private def find_next_unset_bit(uint : UInt64, size : UInt64)
        size.times do |off|
          return off if (uint & (1u64 << off)) == 0
        end

        raise "#find_next_* is broken"
      end

      private def find_index(list)
        list.each_with_index do |el, idx|
          return idx if yield(el)
        end

        nil
      end

      private def uint64_slice
        ptr = @data.pointer(@data.size).as(UInt64*)
        byte_off = @data.size & ~(BITS_PER_BYTE - 1)
        big_size = @data.size / sizeof(UInt64)

        # If the bit-count is NOT divisble by 64 bit, but the total byte count
        # is, let the trailer be the last 8 byte.
        if !@size.divisible_by?(64) && @data.size.divisible_by?(sizeof(UInt64))
          big_size -= 1
          byte_off -= 8
        end

        slice = Slice(UInt64).new(ptr, big_size)
        trailing = @data + byte_off

        { slice, trailing, byte_off }
      end
    end
  end
end
