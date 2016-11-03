module Torrent
  module Extension
    # Implements BEP-0011: Peer Exchange (PEX)
    class PeerExchange < Handler
      def initialize(manager)
        super "ut_pex", manager

        @log = Util::Logger.new("Ext/PEX")
        @log.info "Added Peer Exchange extension to #{manager}"
      end

      def invoke(peer : Client::Peer, payload : Bytes)
        @log.debug "Peer exchanged peers with us"
        peers = Payload.from_bencode(payload)
        add_peers peer, peers.added, "IPv4"
        add_peers peer, peers.added6, "IPv6"
        @manager.peer_list.connect_to_candidates
      end

      private def add_peers(peer, list, type)
        return if list.nil?

        @log.debug "Peer #{peer.address} #{peer.port} knows of #{list.size} #{type} peers"
        list.each do |info|
          @manager.peer_list.add_candidate_bulk peer.transfer, info.address, info.port.to_u16
        end
      end

      @[Flags]
      enum PeerFlag : UInt8

        # This peer wants to encrypt the connection
        PreferEncryption = 0x01

        # This peer is a seed-box
        SeedOnly = 0x02

        # This peer supports the µTP protocol
        SupportsUtp = 0x04

        # This peer supports the "ut_holepunch" extension.
        # This extension is undocumented.
        SupportsHolepunch = 0x08

        # This peer is reachable over the Internet
        Reachable = 0x10
      end

      struct Payload
        Bencode.mapping(
          added: { type: Array(Structure::PeerInfo), converter: Structure::PeerInfoConverter, nilable: true },
          added_flags: { type: Array(PeerFlag), nilable: true },
          added6: { type: Array(Structure::PeerInfo), converter: Structure::PeerInfo6Converter, nilable: true },
          added6_flags: { type: Array(PeerFlag), nilable: true },
          dropped: { type: Array(Structure::PeerInfo), converter: Structure::PeerInfoConverter, nilable: true },
          dropped6: { type: Array(Structure::PeerInfo), converter: Structure::PeerInfo6Converter, nilable: true },
        )
      end

      module FlagConverter
        def self.from_bencode(pull)
          pull.read_byte_slice.map do |flag|
            PeerFlag.from_value(flag)
          end
        end

        def self.to_bencode(list, io)
          Slice(UInt8).new(list.to_unsafe.as(UInt8*), list.size).to_bencode(io)
        end
      end
    end
  end
end
