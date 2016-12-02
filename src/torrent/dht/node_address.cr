module Torrent
  module Dht
    lib Native
      @[Packed]
      struct V4
        node_id : UInt8[20]
        address : UInt8[4]
        port : UInt16
      end
    end

    # Stores the remote address and the remote nodes id.  Can be used to send
    # node information over the network, or to persist (and later load again)
    # it.
    class NodeAddress

      # The network address
      getter address : String

      # The network port
      getter port : UInt16

      # The remote nodes id
      getter id : BigInt

      # If the address uses IPv6, uses IPv4 if `false`
      getter? v6 : Bool

      def initialize(@address, @port, @id, @v6)
      end

      def_equals_and_hash @address, @port, @id

      # Reads the node address from its "compact" representation
      def initialize(native : Native::V4)
        @address = native.address.join '.'
        @port = Util::Endian.to_host native.port
        @id = Util::Gmp.import_sha1 native.node_id.to_slice
        @v6 = false
      end

      # Kademlia distance based on the `#id`.
      def kademlia_distance(other : BigInt)
        @id ^ other
      end

      # Returns the address as compact representation
      def to_native : Native::V4
        v4 = Native::V4.new
        parts = @address.split('.').map(&.to_u8).to_a
        v4.address = StaticArray[ parts[0], parts[1], parts[2], parts[3] ]

        exported = Util::Gmp.export_sha1 @id
        v4.node_id.to_slice.copy_from exported
        v4
      end

      # Loads multiple addresses from a slice of concatenated compact
      # representations.
      def self.from_compact(slice : Bytes) : Array(NodeAddress)
        raise ArgumentError.new("Slice size not divisble by 26") unless slice.size.divisible_by? 26

        count = slice.size / 26
        ptr = slice.pointer(slice.size).as(Native::V4*)
        natives = Slice(Native::V4).new(ptr, count)

        Array(NodeAddress).new(count){|idx| NodeAddress.new natives[idx]}
      end

      # Stores a *list* of node addresses into a concatenated compact byte
      # slice.
      def self.to_compact(list : Indexable(NodeAddress)) : Bytes
        natives = Slice(Native::V4).new(list.size) do |idx|
          list[idx].to_native
        end

        ptr = natives.pointer(natives.size).as(UInt8*)
        Bytes.new(ptr, list.size * 26)
      end
    end
  end
end
