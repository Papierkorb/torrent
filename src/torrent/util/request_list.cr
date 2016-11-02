module Torrent
  module Util
    class RequestList
      class Piece

        # The piece to copying
        getter index : UInt32

        # Total size of the piece
        getter size : UInt32

        # Size of each block in bytes
        getter block_size : UInt32

        # Block completion status
        getter progress : Array(Bool)

        # Count of blocks in the piece
        getter count : Int32

        # Moment the piece was requested
        getter request_time : Time

        def initialize(@index, @size, @block_size)
          @count = (@size / @block_size).to_i32
          @count += 1 unless @size.divisible_by? @block_size
          @progress = Array(Bool).new(@count, false)
          @request_time = Time.now
        end

        def complete? : Bool
          @progress.all?{|el| el == true}
        end

        def complete?(block_idx) : Bool
          @progress[block_idx]
        end

        def offset_to_block(offset)
          raise ArgumentError.new("Invalid offset: Not divisible by block size") unless offset.divisible_by?(@block_size)

          offset / @block_size
        end

        def mark_complete(block_idx)
          @progress[block_idx] = true
          complete?
        end

        def to_a
          Array.new(@count) do |idx|
            tuple(idx)
          end
        end

        def tuple(block_index)
          off = block_index.to_u32 * @block_size
          size = @block_size

          # The very last block is most likely shorter than the standard block
          # size.
          if !@size.divisible_by?(size) && block_index + 1 == @progress.size
            size = @size % @block_size
          end

          { @index, off, size }
        end
      end

      # Size of requested blocks in a piece. 16KiB looks to be a popular value.
      REQUEST_BLOCK_SIZE = (16 * 1024).to_u32

      # Bitfield given out to clients. Only contains completed pieces.
      getter public_bitfield : Bitfield

      # Bitfield for book-keeping. Contains completed and in-progress pieces.
      getter private_bitfield : Bitfield

      # Total size of the torrent
      getter total_size : UInt64

      # Open piece requests
      getter pieces : Array(Tuple(Client::Peer, Piece))

      def initialize(piece_count, @total_size : UInt64)
        @public_bitfield = Bitfield.new(piece_count)
        @private_bitfield = @public_bitfield.clone
        @pieces = Array(Tuple(Client::Peer, Piece)).new
      end

      def find_piece(piece_index : UInt32)
        @pieces.find do |_peer, piece|
          piece.index == piece_index
        end
      end

      def find_piece(peer : Client::Peer, piece_index : UInt32)
        @pieces.each do |remote_peer, piece|
          return piece if peer == remote_peer && piece.index == piece_index
        end

        nil
      end

      # Cancels the download of *piece* from *peer*.
      def cancel_piece(peer, piece : Piece)
        idx = find_index(peer, piece){ nil }
        return if idx.nil?
        @pieces.delete_at(idx)

        # Clear piece from private bitfield IF no other peer is downloading it.
        # This happens in end-game mode.
        if @pieces.find{|_peer, other_piece| other_piece.index == piece.index}.nil?
          @private_bitfield[piece.index] = false
        end
      end

      # Cancels all requests of *peer*.
      def cancel_all_pieces(peer)
        @pieces.reject! do |remote_peer, piece|
          if remote_peer == peer
            @private_bitfield[piece.index] = false
            true
          end
        end
      end

      # Adds a request to *peer* for *piece_index*, and returns the `Piece`.
      # Also updates the private bitfield.
      def add(peer, piece_index : UInt32) : Piece
        size = peer.transfer.piece_size.to_u32

        @private_bitfield[piece_index] = true # Mark as in progress
        if piece_index == @private_bitfield.size - 1 # Last piece?
          size = last_piece_size(size).to_u32
        end

        piece = Piece.new(piece_index, size, REQUEST_BLOCK_SIZE)
        @pieces << { peer, piece }
        piece
      end

      def finalize_piece(peer, piece)
        idx = find_index(peer, piece){ raise Error.new("Piece not found") }
        @pieces.delete_at(idx)
        @public_bitfield[piece.index] = true
      end

      def pieces_of_peer(peer)
        pieces = Array(Piece).new

        @pieces.each do |remote_peer, piece|
          pieces << piece if remote_peer == peer
        end

        pieces
      end

      # Used for end-game mode to find all peers where a piece was requested
      # from.
      def peers_with_piece(piece_index)
        peers = Array(Client::Peer).new

        @pieces.each do |peer, piece|
          peers << peer if piece.index == piece_index
        end

        peers
      end

      private def last_piece_size(piece_size)
        if @total_size.divisible_by? piece_size
          piece_size
        else
          @total_size % piece_size
        end
      end

      private def find_index(peer, piece)
        @pieces.each_with_index do |(remote_peer, other_piece), idx|
          return idx if peer == remote_peer && other_piece == piece
        end

        yield # Not found block
      end
    end
  end
end
