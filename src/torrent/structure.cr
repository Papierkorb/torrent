module Torrent
  module Structure
    module DateTimeConverter
      def self.from_bencode(pull)
        Time.epoch(pull.read_integer)
      end

      def self.to_bencode(time, io)
        time.epoch.to_bencode(io)
      end
    end

    module HashsumListConverter
      HASHSUM_LENGTH = 20

      def self.from_bencode(pull)
        slice = pull.read_byte_slice

        unless slice.size.divisible_by?(HASHSUM_LENGTH)
          raise "'pieces' is not multiple of #{HASHSUM_LENGTH}, length: #{slice.size}"
        end

        Array(Bytes).new(slice.size / HASHSUM_LENGTH) do |idx|
          slice[idx * HASHSUM_LENGTH, HASHSUM_LENGTH]
        end
      end

      def self.to_bencode(pieces, io)
        total_size = pieces.size * HASHSUM_LENGTH
        io.print "#{total_size}:"

        counted_size = 0
        pieces.each do |piece|
          io.write piece
          counted_size += piece.size
        end

        if counted_size != total_size
          raise "'pieces' array is broken: Expected length #{total_size}, but is actually #{counted_size}"
        end
      end
    end

    module SingleItemArrayConverter
      def self.from_bencode(pull)
        Array(String).new(pull).first
      end

      def self.to_bencode(item, io)
        [ item ].to_bencode(io)
      end
    end

    module AnnounceListConverter
      def self.from_bencode(pull)
        Array(Array(String)).new(pull).flatten
      end

      def self.to_bencode(list, io)
        list.map{|item| [ item ]}.to_a.to_bencode(io)
      end
    end

    module InfoDictionaryConverter
      def self.from_bencode(pull)
        start_pos = pull.peek_token.position
        info = InfoDictionary.new(pull)
        end_pos = pull.peek_token.position

        # Store the raw position in the IO of the `info` hash.
        # We need this later to calculate the `info hash`, as it is NOT
        # calculated using the correct order (by Bencode), but actually is
        # calculated by using the raw data as given in the .torrent file.
        info.raw_range = start_pos...end_pos
        info
      end

      def self.to_bencode(info, io)
        info.to_bencode(io)
      end
    end

    module PeerInfoConverter
      lib Native
        @[Packed]
        struct Data
          address : UInt8[4]
          port : UInt16
        end
      end

      def self.from_bencode(pull)
        list = pull.read_byte_slice
        raise "Peer info list must be multiple of 6" unless list.size.divisible_by? 6

        Array(PeerInfo).new(list.size / 6) do |idx|
          el = list[idx, 6].pointer(6).as(Native::Data*).value

          address = el.address.join(".")
          PeerInfo.new(address, Util::Endian.to_host(el.port).to_i32, false)
        end
      end

      def self.to_bencode(list, io)
        converted = Slice(Native::Data).new(list.size) do |idx|
          info = list[idx]

          parts = info.address.split('.').map(&.to_u8).to_a
          addr = StaticArray[ parts[0], parts[1], parts[2], parts[3] ]
          Native::Data.new(addr, Util::Endian.to_network(info.port.to_u16))
        end

        converted.to_bencode(io)
      end
    end

    module PeerInfo6Converter
      lib Native
        @[Packed]
        struct Data
          address : UInt16[8]
          port : UInt16
        end
      end

      def self.from_bencode(pull)
        list = pull.read_byte_slice
        raise "Peer info list must be multiple of 18" unless list.size.divisible_by? 18

        Array(PeerInfo).new(list.size / 18) do |idx|
          el = list[idx, 18].pointer(18).as(Native::Data*).value

          address = el.address.map{|i| Util::Endian.to_host(i).to_s(16)}.join(":")
          PeerInfo.new(address, Util::Endian.to_host(el.port).to_i32, true)
        end
      end

      def self.to_bencode(list, io)
        converted = Slice(Native::Data).new(list.size) do |idx|
          info = list[idx]

          parts = info.address.split(':').map(&.to_u16).to_a
          addr = StaticArray(UInt16, 8).new{|idx| parts[idx]}
          Native::Data.new(addr, Util::Endian.to_network(info.port.to_u16))
        end

        converted.to_bencode(io)
      end
    end

    # Described in BEP-0003
    class MetaInfo
      Bencode.mapping(

        # Announcing tracker URL
        announce: String,

        #
        announce_list: { type: Array(String), key: "announce-list", converter: AnnounceListConverter, nilable: true },

        # Observed: Creator program of the .torrent file
        created_by: { type: String, key: "created by", nilable: true },

        # Observed: Creation date as UNIX timestamp
        created_at: { type: Time, converter: DateTimeConverter, key: "creation date", nilable: true },

        # Information dictionary on the files
        info: { type: InfoDictionary, converter: InfoDictionaryConverter },
      )
    end

    # Described in BEP-0003
    class InfoDictionary
      Bencode.mapping(
        # If given: Single-file Torrent, size of this file
        length: { type: UInt64, nilable: true },

        # If given: Multi-file Torrent
        files: { type: Array(SingleFileInfo), nilable: true },

        # Name of the top-level file or directory
        name: String,

        # Size of a piece (Block of data)
        piece_length: { type: UInt64, key: "piece length" },

        # List of SHA-1 sums
        pieces: { type: Array(Bytes), converter: HashsumListConverter },

        # Is this a private torrent?
        private: { type: Bool, default: false },
      )

      # Byte range in the source file
      property raw_range : Range(Int32, Int32)?

      # The info hash as unparsed raw data.
      # Will be set by `Torrent::File`.
      property raw_data : Bytes?
    end

    # Described in BEP-0003
    class SingleFileInfo
      Bencode.mapping(

        # Size of the file
        length: UInt64,

        # Pathname of the file
        path: { type: String, converter: SingleItemArrayConverter },
      )

      def initialize(@path, @length)
      end
    end

    class PeerList
      Bencode.mapping(

        # Interval in seconds between rerequests
        interval: UInt32,

        # List of peers (IPv4)
        peers: { type: Array(PeerInfo), converter: PeerInfoConverter, default: Array(PeerInfo).new },

        # List of peers (IPv6)
        peers6: { type: Array(PeerInfo), converter: PeerInfo6Converter, default: Array(PeerInfo).new },
      )
    end

    struct PeerInfo
      # The peer address (IPv4 or v6)
      getter address : String

      # The port the peer is listening on
      getter port : Int32

      # Is this an IPv6 address?
      getter? v6 : Bool

      def initialize(@address, @port, @v6)
      end
    end

    struct ScrapeResponse
      Bencode.mapping(
        # Mapping from the info hash to the metadata.
        # Attention: The info hash is not a readable string!
        files: Hash(String, ScrapeMetadata),
      )
    end

    struct ScrapeMetadata
      Bencode.mapping(
        # Number of active peers that have completed downloading
        complete: UInt64,

        # Number of active peers that have not completed downloading
        incomplete: UInt64,

        # Number of peers that have ever completed downloading
        downloaded: UInt64,
      )
    end

    # Handshake dictionary of the protocol extension mechanism.
    # Part of BEP-0010.
    struct ExtendedHandshake
      Bencode.mapping(
        # Mapping from the extension name to the message id
        mapping: { type: Hash(String, UInt8), key: "m" },

        # Local TCP listen port
        listen_port: { type: UInt16, nilable: true, key: "p" },

        # Client version and number, human-readable UTF-8 string
        client: { type: String, nilable: true, key: "v" },

        # The IP the sending peer sees the receiving peer as
        yourip: { type: Bytes, nilable: true },

        # This peers IPv6 address in compact form
        ipv6: { type: Bytes, nilable: true },

        # This peers IPv4 address in compact form
        ipv4: { type: Bytes, nilable: true },

        # Number of outstanding requests messages
        reqq: { type: Int32, nilable: true },

        # BEP-0009: Size of the metadata ("info") dictionary
        metadata_size: { type: Int32, nilable: true },
      )

      setter listen_port
      setter client
      setter yourip
      setter ipv6
      setter ipv4
      setter reqq
      setter metadata_size

      def initialize
        @mapping = Hash(String, UInt8).new
      end
    end
  end
end
