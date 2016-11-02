module Torrent
  module PiecePicker
    # A piece picker which picks pieces sequentially, from the first one till the
    # last one.
    #
    # Transfers using this picker are **not** regarded as being "well-behaved",
    # but this strategy can still be useful if the user wants to stream-read a
    # large file.
    class Sequential < Base
      def pick_piece(peer : Client::Peer) : UInt32?
        peer_bits = peer.bitfield
        my_bits = peer.transfer.requests.private_bitfield

        my_bits.each(false) do |idx|
          return idx.to_u32 if peer_bits[idx]
        end

        nil
      end

      def unpick_piece(piece : UInt32)
        # Do nothing.
      end
    end
  end
end
