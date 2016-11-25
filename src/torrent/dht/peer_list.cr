module Torrent
  module Dht
    # Stores known peers for
    class PeerList
      alias PeerData = Torrent::Structure::PeerInfoConverter::Native::Data

      # Max count of peers per list.
      MAX_PEERS = 1000

      # Timeouts for peers in the list.
      PEER_TIMEOUT = 45.minutes

      # Peers in compact format, ready to be sent out.
      getter peers : Array(Tuple(Time, Bytes))

      # The info hash
      getter info_hash : BigInt

      def initialize(@info_hash : BigInt)
        short = Util::Gmp.export_sha1(@info_hash)[0, 10]
        @log = Util::Logger.new("Dht/PeerList #{short.hexstring}")
        @peers = Array(Tuple(Time, Bytes)).new
      end

      def kademlia_distance(other)
        @info_hash ^ other
      end

      def any_sample(count = Bucket::MAX_NODES * 2)
        @peers.sample(count).map do |_ign, native|
          Bencode::Any.new(native)
        end.to_a
      end

      # Checks for timeouts, removing those which we have not seen in a while.
      def check_timeouts
        timeout_at = Time.now - PEER_TIMEOUT
        @peers.reject!{|time, _ign| time < timeout_at}
      end

      # Adds (or updates) a peer at *address:port*
      def add(address : String, port : UInt16) : Nil
        return if peers.size >= MAX_PEERS # Reject if list is full.

        native = Torrent::Structure::PeerInfoConverter.to_native(address, port)
        bytes = Bytes.new(sizeof(PeerData))
        bytes.copy_from(pointerof(native).as(UInt8*), sizeof(PeerData))

        if idx = peers.index{|_ign, data| data == bytes}
          @peers[idx] = { Time.now, @peers[idx][1] }
          @log.info "Heartbeat from #{address}:#{port}"
        else
          @peers << { Time.now, bytes }
          @log.info "Adding #{address}:#{port}"
        end
      end
    end
  end
end
