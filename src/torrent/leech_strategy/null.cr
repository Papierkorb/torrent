module Torrent
  module LeechStrategy
    # Null leech strategy.  Will reject any candidate and not try to request any
    # piece at all.
    class Null < Base
      def candidate_ranking(address : String, port : UInt16) : Int32
        0
      end

      def peer_added(peer : Client::Peer) : Nil
        # Do nothing.
      end
    end
  end
end
