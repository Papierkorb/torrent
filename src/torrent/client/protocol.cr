require "./wire"

module Torrent
  module Client
    module Protocol
      struct Handshake < Util::NetworkOrderStruct(Wire::Handshake)
        NAME = "BitTorrent protocol"
        NAME_LEN = 19

        fields(
          length : UInt8,
          name : UInt8[NAME_LEN],
          reserved : UInt8[8],
        )

        # Builds a new handshake packet
        def self.create
          wire = Wire::Handshake.new
          wire.length = NAME_LEN.to_u8
          NAME.to_slice.copy_to(wire.name.to_slice)
          wire.reserved[5] = 0x10u8 # Extension protocol
          wire.reserved[7] = 0x04u8 # Fast Extension

          self.new(wire)
        end

        # Verifies the handshake packet. Raises if anything looks wrong.
        def verify!
          raise Error.new("Wrong length: #{length}") if length != NAME_LEN

          protocol = String.new(name.to_slice)
          raise Error.new("Wrong name: #{protocol.inspect}") if protocol != NAME

          # TODO: Verify extensions in `reserved`
        end

        def extension_protocol?
          (reserved[5] & 0x10u8) != 0
        end

        def fast_extension?
          (reserved[7] & 0x04u8) != 0
        end
      end

      # Dummy structure to store the packet size
      struct PacketSize < Util::NetworkOrderStruct(Wire::PacketSize)
        fields(size : UInt32)
      end

      struct PacketPreamble < Util::NetworkOrderStruct(Wire::PacketPreamble)
        fields(
          size : UInt32,
          id : UInt8,
        )
      end

      struct Have < Util::NetworkOrderStruct(Wire::Have)
        fields(piece : UInt32)
      end

      # Same payload
      alias SuggestPiece = Have

      struct Request < Util::NetworkOrderStruct(Wire::Request)
        fields(
          index : UInt32,
          start : UInt32,
          length : UInt32,
        )
      end

      # Same payloads
      alias Cancel = Request
      alias RejectRequest = Request

      struct Piece < Util::NetworkOrderStruct(Wire::Piece)
        fields(
          index : UInt32,
          offset : UInt32,
          # Data ...
        )
      end

      struct Extended < Util::NetworkOrderStruct(Wire::Extended)
        fields(
          message_id : UInt8,
        )
      end

      # UDP tracker

      struct TrackerConnectRequest < Util::NetworkOrderStruct(Wire::TrackerConnectRequest)
        fields(
          connection_id : UInt64,
          action : Int32, # = TrackerAction::Connect
          transaction_id : UInt32,
        )
      end

      struct TrackerConnectResponse < Util::NetworkOrderStruct(Wire::TrackerConnectResponse)
        fields(
          action : Int32, # = TrackerAction::Connect
          transaction_id : UInt32,
          connection_id : UInt64,
        )
      end

      struct TrackerAnnounceRequest < Util::NetworkOrderStruct(Wire::TrackerAnnounceRequest)
        fields(
          connection_id : UInt64,
          action : Int32, # = TrackerAction::Announce
          transaction_id : UInt32,
          info_hash : UInt8[20],
          peer_id : UInt8[20],
          downloaded : UInt64,
          left : UInt64,
          uploaded : UInt64,
          event : Int32,
          ip_address : UInt32, # default: 0
          key : UInt32,
          num_want : Int32, # default: -1
          port : UInt16,
        )
      end

      struct TrackerAnnounceResponse < Util::NetworkOrderStruct(Wire::TrackerAnnounceResponse)
        fields(
          action : Int32, # = TrackerAction::Announce
          transaction_id : UInt32,
          interval : Int32,
          leechers : Int32,
          seeders : Int32,
          # v4 addresses: 4 * x Bytes
          # v4 ports: 2 * x Bytes
        )
      end
    end
  end
end
