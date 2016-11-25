module Torrent

  # Structure for the wire protocol
  #
  # ## The BitTorrent protocol
  #
  # The connection handshake is as follows:
  # 1. Send the Handshake packet
  # 2. Send the SHA-1 hash of the bencoded `info` dictionary of the .torrent file
  # 3. Send the 20-Byte peer id as was given to the tracker
  # 4. The connection is now ready
  #
  # All of the above packets are sent by both peer to the other peer.
  # If any of the data makes no sense, the connection is closed.
  #
  # **Note:** A seeding peer may wait for the SHA-1 hash so it can react to
  #           download requests while offering many files at once.
  #
  # At this point, peers can exchange messages. The format is:
  # 1. UInt32: Size of the following data
  # 2. UInt8: The message type (See `Wire::MessageType`)
  # 3. Following bytes are the message payload
  #
  # **Note:** The protocol uses network byte-order (Big-Endian).
  lib Wire

    # Peer messages
    enum MessageType : UInt8

      # No payload.
      Choke = 0

      # No payload.
      Unchoke = 1

      # No payload.
      Interested = 2

      # No payload.
      NotInterested = 3

      Have = 4
      Bitfield = 5
      Request = 6
      Piece = 7
      Cancel = 8

      # BEP-0005: DHT Protocol
      Port = 9

      # BEP-0006: Fast Extension

      SuggestPiece = 0x0D
      HaveAll = 0x0E
      HaveNone = 0x0F
      RejectRequest = 0x10
      AllowedFast = 0x11

      # BEP-0010
      Extended = 20
    end

    # Protocol handshake, is the first package sent and received.
    @[Packed]
    struct Handshake
      length : UInt8 # == 19
      name : UInt8[19] # "BitTorrent protocol"
      reserved : UInt8[8] # == 0
    end

    @[Packed]
    struct PacketSize
      size : UInt32 # Size of the following packet
    end

    @[Packed]
    struct PacketPreamble
      size : UInt32 # Size of the following packet
      id : UInt8
    end

    @[Packed]
    struct Have
      piece : UInt32
    end

    @[Packed]
    struct Request
      index : UInt32
      start : UInt32
      length : UInt32
    end

    @[Packed]
    struct Piece
      index : UInt32
      offset : UInt32
      # data ...
    end

    @[Packed]
    struct Extended
      message_id : UInt8
    end

    @[Packed]
    struct DhtPort
      port : UInt16
    end

    # UDP tracker protocol
    enum TrackerAction : Int32
      Connect = 0
      Announce = 1
      Scrape = 2
      Error = 3
    end

    enum TrackerEvent : Int32
      None = 0
      Completed = 1
      Started = 2
      Stopped = 3
    end

    @[Packed]
    struct TrackerConnectRequest
      connection_id : UInt64
      action : Int32 # = TrackerAction::Connection
      transaction_id : UInt32
    end

    @[Packed]
    struct TrackerConnectResponse
      action : Int32 # = TrackerAction::Connection
      transaction_id : UInt32
      connection_id : UInt64
    end

    @[Packed]
    struct TrackerAnnounceRequest
      connection_id : UInt64
      action : Int32 # = TrackerAction::Announce
      transaction_id : UInt32
      info_hash : UInt8[20]
      peer_id : UInt8[20]
      downloaded : UInt64
      left : UInt64
      uploaded : UInt64
      event : Int32
      ip_address : UInt32 # default: 0
      key : UInt32 # default: 0
      num_want : Int32 # default: -1
      port : UInt16
    end

    @[Packed]
    struct TrackerAnnounceResponse
      action : Int32 # = TrackerAction::Announce
      transaction_id : UInt32
      interval : Int32
      leechers : Int32
      seeders : Int32
      # v4 addresses: 4 * x Bytes
      # v4 ports: 2 * x Bytes
    end
  end
end
