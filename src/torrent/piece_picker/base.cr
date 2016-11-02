module Torrent
  module PiecePicker
    abstract class Base
      # Called when a piece is to be picked for *peer*. The implementation then
      # returns the piece index to download, or `nil` if no piece shall be
      # requested.
      abstract def pick_piece(peer : Client::Peer) : UInt32?

      # Called when a piece timed out and should be put back into the picking
      # pool.
      abstract def unpick_piece(piece : UInt32)
    end
  end
end
