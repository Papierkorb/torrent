module Torrent
  module LeechStrategy
    # The default leech strategy.  Aims to implement a useful, default strategy
    # for a well-behaved BitTorrent peer.
    #
    # ## Strategy
    #
    # At first, each connected peer which has a piece we don't (and has unchoked
    # us), gets a request.  This is done for a few pieces until we can estimate
    # the average download-time of a piece.  Then the fastest peers are sent
    # more concurrent requests.
    #
    # If all remaining pieces are in-transit (have been requested), the strategy
    # enters the so called End-Game mode.  All connected peers are then sent
    # requests for *all* pieces (up to the point of their maximum concurrent
    # request count of course).  Then after the first piece sent us the first
    # block of a piece, all other requests for the same piece to other peers
    # are cancelled.
    class Default < Base

      # Threshold of piece count a peer must have completed before being
      # able to be promoted to a "fast" peer.
      FAST_PIECE_THRESHOLD = 5

      # A transfer rate of more than one piece per time is considered "fast"
      FAST_PER_PIECE_TIME = 1.second

      MAX_OPEN_REQUESTS_PER_PEER = Torrent::Transfer::MAX_OPEN_REQUESTS_PER_PEER
      MAX_OPEN_REQUESTS = Torrent::Transfer::MAX_OPEN_REQUESTS

      record Statistic,
        download_time : Time::Span,
        piece_count : Int32

      # Download statistics of each active peer.
      getter statistics : Hash(Client::Peer, Statistic)

      # Is the transfer in end-game mode?
      getter? end_game_mode : Bool = false

      # Emitted when the end-game mode has been entered
      Cute.signal end_game_mode_entered

      def initialize
        @statistics = Hash(Client::Peer, Statistic).new
        @log = Util::Logger.new("Leech/Default")
      end

      def start(transfer)
        super

        Util.spawn do
          loop do
            sleep Torrent::Transfer::PIECE_CHECK_INTERVAL
            check_piece_timeouts
          end
        end
      end

      # Returns if the *peer* is "fast".  A fast peer is one which completes
      # a whole piece request in a second or less.  If less than a threshold
      # amount of pieces have been requested yet, the result will be `false`.
      def fast_peer?(peer) : Bool
        stats = @statistics[peer]
        return false if stats.piece_count < FAST_PIECE_THRESHOLD

        time_per_piece = stats.download_time / stats.piece_count
        (time_per_piece <= FAST_PER_PIECE_TIME)
      end

      def peer_added(peer : Client::Peer) : Nil
        @statistics[peer] = Statistic.new(Time::Span.new(0), 0)

        peer.connection_lost.on{ on_peer_removed peer }
        peer.status_bit_set.on{|bit| on_status_bit_set peer, bit}
        peer.status_bit_cleared.on{|bit| on_status_bit_clear peer, bit}
        peer.piece_download_completed.on{|piece, data| on_piece_download_complete peer, piece, data}
        peer.have_received.on{|_piece| request_piece_if_possible peer}
        peer.bitfield_received.on{ request_piece_if_possible(peer) }
        peer.request_rejected.on{|rej| on_request_rejected peer, rej}
      end

      private def on_request_rejected(peer, rej)
        piece = transfer.requests.find_piece peer, rej.index
        return if piece.nil?

        transfer.requests.cancel_piece peer, piece
        reschedule_or_unpick_piece rej.index
      end

      private def check_for_end_game
        return if @end_game_mode
        return unless transfer.requests.private_bitfield.all_ones?

        @end_game_mode = true
        start_end_game
      end

      # Starts the end-game mode. In this mode, all missing pieces are requested
      # from all peers having that peer (and not choking us). The first peer
      # sending us the piece "wins", and the piece is cancelled at all other
      # peers.
      private def start_end_game
        @log.info "Entering end-game mode!"
        end_game_mode_entered.emit

        transfer.requests.public_bitfield.each(false) do |idx|
          @log.debug "Requesting piece #{idx} as part of the end-game"
          request_piece_from_all idx.to_u32
        end
      end

      private def request_piece_from_all(piece_index : UInt32)
        transfer.manager.peers.each do |peer|
          request_specific_piece_if_possible peer, piece_index
        end
      end

      # TODO: Move this back into `Transfer`?
      private def on_status_bit_set(peer, status : Client::Peer::Status)
        if status.choked_by_peer?
          transfer.requests.cancel_all_pieces(peer) unless peer.fast_extension?
        end
      end

      private def on_status_bit_clear(peer, status : Client::Peer::Status)
        if status.choked_by_peer? # No longer choked?
          request_piece_if_possible(peer)
        end
      end

      # Called by `Client::Peer` when a request has been downloaded completely.
      private def on_piece_download_complete(peer, peer_piece : Client::Protocol::Piece, data : Bytes)
        piece = find_request_by_piece(peer, peer_piece.index, peer_piece.offset, data.size)
        transfer.downloaded += data.size

        transfer.write_piece(peer_piece.index, peer_piece.offset, data)
        maybe_cancel_for_others(peer, piece.index) if @end_game_mode

        return unless piece.complete?
        if validate_piece(peer, piece.index, piece.size)
          update_statistics peer, piece

          announce_valid_piece(peer, piece.index, piece.size)
          request_piece_if_possible(peer)

        else
          announce_broken_piece(peer, piece.index, piece.size)
        end
      rescue error
        @log.error "Failed to handle completed piece request"
        @log.error error
      end

      private def update_statistics(peer, piece)
        time_taken = Time.now - piece.request_time
        stats = @statistics[peer]
        @statistics[peer] = Statistic.new(
          download_time: stats.download_time + time_taken,
          piece_count: stats.piece_count + 1
        )
      end

      # End-Game mode: Cancel for other peers if the peer sent us 75% of the
      # piece.  This is quite greedy.
      private def maybe_cancel_for_others(peer, piece_index)
        piece = transfer.requests.find_piece(peer, piece_index)
        if piece && piece.count_done >= (piece.count * 0.75).to_i
          cancel_piece_for_others(piece_index, peer)
        end
      end

      private def cancel_piece_for_others(piece_index, except_peer)
        @log.info "Cancelling piece #{piece_index} for other peers"

        transfer.requests.peers_with_piece(piece_index).each do |peer|
          next if peer == except_peer
          piece = transfer.requests.find_piece(peer, piece_index)
          cancel_piece(peer, piece) if piece
        end
      end

      private def request_piece_if_possible(peer) : Nil
        return if peer.status.choked_by_peer?
        return if transfer.requests.pieces.size >= MAX_OPEN_REQUESTS

        open_requests = transfer.requests.pieces_of_peer(peer).size
        return if open_requests >= MAX_OPEN_REQUESTS_PER_PEER
        return false if open_requests >= peer.max_concurrent_piece_requests

        # Request many pieces from fast peers, and only one from slow peers.
        pieces = 1
        pieces = peer.max_concurrent_piece_requests if fast_peer?(peer)
        max_new = MAX_OPEN_REQUESTS_PER_PEER - open_requests
        pieces.clamp(1, max_new).times{ request_new_piece(peer) } if max_new > 0
        check_for_end_game
      end

      private def request_specific_piece_if_possible(peer, piece_index) : Bool
        return false if peer.status.choked_by_peer?
        return false unless peer.bitfield[piece_index]
        return false if transfer.requests.pieces.size >= MAX_OPEN_REQUESTS

        open_requests = transfer.requests.pieces_of_peer(peer).size
        return false if open_requests >= MAX_OPEN_REQUESTS_PER_PEER
        return false if open_requests >= peer.max_concurrent_piece_requests
        return false if !@end_game_mode && transfer.requests.find_piece(piece_index)

        request_specific_piece(peer, piece_index)
        check_for_end_game
        true
      end

      private def announce_valid_piece(peer, index, length)
        pieces_done = transfer.requests.public_bitfield.count(true)
        pieces_total = transfer.requests.public_bitfield.size
        @log.info "Finished download of piece #{index}"

        transfer.piece_ready.emit(peer, index, length)
        if pieces_done == pieces_total
          transfer.change_status Transfer::Status::Completed
        end
      end

      private def announce_broken_piece(peer, index, length)
        transfer.requests.private_bitfield[index] = false
        transfer.broken_piece_received.emit(peer, index, length)
      end

      private def validate_piece(peer, index, length) : Bool
        digest = calculate_piece_hashsum(index, length)
        correct = transfer.file.sha1_sums[index]

        digest.to_slice == correct
      end

      private def calculate_piece_hashsum(index, length)
        buffer = Bytes.new(length)
        transfer.read_piece(index, 0, buffer)
        Digest::SHA1.digest(buffer)
      end

      private def request_new_piece(peer)
        @log.info "Requesting next missing piece"
        piece_index = transfer.piece_picker.pick_piece(peer)

        if piece_index.nil?
          @log.info "Wanted to request another piece, but all pieces have been requested at this point for this peer."
          return
        end

        request_specific_piece peer, piece_index
      end

      private def request_specific_piece(peer, piece_index)
        @log.info "Requesting piece #{piece_index} from #{peer}"

        piece = transfer.requests.add(peer, piece_index)
        piece.to_a.each do |index, offset, length|
          peer.send_request(index, offset, length)
        end
      rescue error
        @log.error "Failed to send request. Cancelling from request list."
        @log.error error
        transfer.requests.cancel_piece(peer, piece) if piece
      end

      private def find_request_by_piece(peer, piece_index, offset, length)
        piece = transfer.requests.find_piece(peer, piece_index)

        if piece.nil?
          raise Error.new("Peer #{peer.address}:#{peer.port} responded with unknown piece #{piece_index} offset #{offset} length #{length}")
        end

        block_idx = sanity_check_request piece, offset, length
        check_if_request_is_complete(peer, piece, block_idx)
        piece
      end

      private def sanity_check_request(piece, offset, length)
        if length != piece.block_size && offset + length != piece.size
          raise Error.new("Peer sent invalid block size: Wanted #{piece.block_size}, but got #{length}")
        end

        block_idx = piece.offset_to_block(offset)
        if piece.complete?(block_idx)
          raise Error.new("Peer has sent a block which has already been sent")
        end

        block_idx
      end

      private def check_if_request_is_complete(peer, piece, block_idx)
        if piece.mark_complete(block_idx)
          transfer.requests.finalize_piece(peer, piece)
        end
      end

      private def check_piece_timeouts
        now = Time.now

        transfer.requests.pieces.each do |peer, piece|
          timeout_at = piece.request_time + Torrent::Transfer::PIECE_TIMEOUT
          next unless timeout_at < now
          cancel_piece_due_to_timeout peer, piece
          reschedule_or_unpick_piece piece.index
        end
      rescue error
        @log.error "Error in #check_piece_timeouts"
        @log.error error
        exit 1
      end

      private def reschedule_or_unpick_piece(piece_index)
        unless reschedule_piece(piece_index)
          transfer.piece_picker.unpick_piece(piece_index)
        end
      end

      private def reschedule_piece(piece_index)
        if @end_game_mode
          request_piece_from_all piece_index
        else
          transfer.manager.peers.shuffle.find do |peer|
            request_specific_piece_if_possible(peer, piece_index)
          end
        end
      end

      private def cancel_piece(peer, piece : Util::RequestList::Piece)
        transfer.requests.cancel_piece(peer, piece)

        begin
          piece.to_a.each do |index, offset, size|
            peer.send_cancel(index, offset, size)
          end
        rescue err
          # Ignore.
        end
      end

      private def cancel_piece_due_to_timeout(peer, piece)
        @log.info "Cancelling request of piece #{piece.index}: Timeout"
        cancel_piece(peer, piece)

        transfer.piece_timeout.emit(peer, piece)
        peer.close # TODO: Should we really just close the connection?
      end

      # Reschedules pieces of dropped peers
      private def on_peer_removed(peer)
        @statistics.delete peer

        transfer.requests.pieces_of_peer(peer).each do |piece|
          transfer.requests.cancel_piece peer, piece
          reschedule_or_unpick_piece piece.index
        end
      end
    end
  end
end
