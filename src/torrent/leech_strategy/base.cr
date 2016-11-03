module Torrent
  module LeechStrategy
    # Base class for leech-strategies.  Their job is to control which peers are
    # connected to and which piece is requested from each peer.  The
    # leech-strategy is specific to a `Torrent::Transfer`.
    #
    # See also `PiecePicker`
    abstract class Base
      @transfer : Torrent::Transfer?

      # Starts the strategy.
      def start(transfer : Torrent::Transfer)
        @transfer = transfer
      end

      # Returns the transfer after the start.
      def transfer
        @transfer.not_nil!
      end

      # Called by `Torrent::PeerList` to compute the ranking of a candidate.
      # The ranking is a number between 0 and 100 inclusive. If the ranking is
      # zero, the candidate will be skipped. If it's 100, it will be added to
      # the top of the peer list (after other peers with a 100 ranking), making
      # it much more likely to be connected to than a peer with a lower ranking.
      #
      # This mechanism can be used to connect to peers which are geographically
      # nearer to the local client. The default implementation always returns
      # 100.
      def candidate_ranking(address : String, port : UInt16) : Int32
        100
      end

      # Called whenever a new *peer* has been connected to.
      abstract def peer_added(peer : Client::Peer) : Nil
    end
  end
end
