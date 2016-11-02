module Torrent
  # Stores data about a single torrent transfer
  class Transfer
    PEER_ID_LENGTH = 20
    PEER_ID_PREAMBLE = "-CR0001-"
    PEER_ID_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    # Maximum count of open requests to download pieces *from* peers
    MAX_OPEN_REQUESTS = 100

    MAX_OPEN_REQUESTS_PER_PEER = 4

    # Cancel a piece request after some time if it's still running.
    PIECE_TIMEOUT = 1.minute

    #
    PIECE_CHECK_INTERVAL = 10.seconds

    # Transfer states
    enum Status

      # The transfer has stopped. Initial status.
      Stopped

      # The transfer is currently running.
      Running

      # The transfer has completed.
      Completed
    end

    # The transfer status
    property status : Status = Status::Stopped

    # The torrent file
    getter file : Torrent::File

    # The used transfer manager
    getter manager : Manager::Base

    # The peer-id used for this transfer
    getter peer_id : String

    # Total uploaded size in bytes
    property uploaded : UInt64

    # Total downloaded size in bytes
    property downloaded : UInt64

    # Open requests to download pieces from remote peers
    # getter open_requests : Array(Tuple(Client::Peer, Util::RequestList::Piece))

    # Manages piece requests
    getter requests : Util::RequestList

    # The used piece picker
    property piece_picker : PiecePicker::Base

    # Is the transfer in end-game mode?
    getter? end_game_mode : Bool = false

    delegate info_hash, total_size, piece_count, piece_size, private?, to: @file

    # Emitted when the status has changed
    Cute.signal status_changed(status : Status)

    # Emitted when a piece has been fully received and validated.
    # *length* is the length of the piece.
    Cute.signal piece_ready(peer : Client::Peer, piece_index : UInt32, length : UInt32)

    # Emitted when the download has been completed
    Cute.signal download_completed

    # Emitted when a piece has been fully received from *peer*, but validation
    # failed.
    Cute.signal broken_piece_received(peer : Client::Peer, piece_index : UInt32, length : UInt32)

    # Emitted when a piece has timeouted and subsequently cancelled.
    Cute.signal piece_timeout(peer : Client::Peer, piece : Util::RequestList::Piece)

    def initialize(@file, @manager,
      @uploaded = 0u64, @downloaded = 0u64, peer_id = nil,
      @status = Status::Stopped, @piece_picker = PiecePicker::Sequential.new)
      @peer_id = peer_id || Transfer.generate_peer_id

      @requests = Util::RequestList.new(@file.piece_count, @file.total_size)
      @log = Util::Logger.new("Transfer")

      @log.context = "Transfer/#{@file.info_hash[0, 10].hexstring}"
    end

    # Returns the count of bytes left to download
    def left
      total_size - @downloaded
    end

    # Returns the download/upload ratio. If nothing has been transferred yet
    # in either direction, `0.0` is returned.
    def transfer_ratio : Float64
      return 0.0 if @uploaded == 0 || @downloaded == 0
      @uploaded.to_f64 / @downloaded.to_f64
    end

    # Returns the count of pieces which have been successfully downloaded.
    # See also `File#piece_count`.
    def pieces_done
      @requests.public_bitfield.count(true)
    end

    # Like `#read_piece`, but also increments `#uploaded`
    def read_piece_for_upload(piece : Int, offset, buffer) : Nil
      read_piece(piece, offset, buffer)
      @uploaded += buffer.size
    end

    # Reads data from the *piece* at *offset* intp *buffer*
    def read_piece(piece : Int, offset, buffer) : Nil
      @file.decode_piece_to_paths(piece, offset, buffer.size).each do |path, off, len|
        @manager.file_manager.read_file(path, off, buffer[0, len])
        buffer += len
      end
    end

    # Writes *buffer* into the *piece* at *offset*
    def write_piece(piece : Int, offset, buffer) : Nil
      @file.decode_piece_to_paths(piece, offset, buffer.size).each do |path, off, len|
        @manager.file_manager.write_file(path, off, buffer[0, len])
        buffer += len
      end
    end

    # Starts the transfer. To be called by the `Manager::Base` implementation.
    def start
      Cute.connect @manager.peer_list.peer_added, on_peer_added(peer)
      Cute.connect @manager.peer_list.peer_removed, on_peer_removed(peer)

      Util.spawn do
        loop do
          sleep PIECE_CHECK_INTERVAL
          check_piece_timeouts
        end
      end
    end

    private def check_piece_timeouts
      now = Time.now

      @requests.pieces.each do |peer, piece|
        next unless piece.request_time + PIECE_TIMEOUT < now
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
        @piece_picker.unpick_piece(piece_index)
      end
    end

    private def reschedule_piece(piece_index)
      if @end_game_mode
        request_piece_from_all piece_index
      else
        @manager.peers.shuffle.find do |peer|
          request_specific_piece_if_possible(peer, piece_index)
        end
      end
    end

    private def cancel_piece(peer, piece : Util::RequestList::Piece)
      @requests.cancel_piece(peer, piece)

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

      piece_timeout.emit(peer, piece)
      peer.close # TODO: Should we really just close the connection?
    end

    private def on_connection_ready(peer)
      peer.send_bitfield(@requests.public_bitfield)
      peer.express_interest if left > 0
      peer.unchoke_peer
    end

    private def on_status_bit_set(peer, status : Client::Peer::Status)
      if status.choked_by_peer?
        @requests.cancel_all_pieces(peer) unless peer.fast_extension?
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
      @downloaded += data.size

      write_piece(peer_piece.index, peer_piece.offset, data)
      cancel_piece_for_others(peer_piece.index, peer) if @end_game_mode

      return unless piece.complete?
      if validate_piece(peer, piece.index, piece.size)
        announce_valid_piece(peer, piece.index, piece.size)
        request_piece_if_possible(peer)
      else
        announce_broken_piece(peer, piece.index, piece.size)
      end
    rescue error
      @log.error "Failed to handle completed piece request"
      @log.error error
    end

    private def cancel_piece_for_others(piece_index, except_peer)
      @log.info "Cancelling piece #{piece_index} for other peers"
      @requests.peers_with_piece(piece_index).each do |peer|
        next if peer == except_peer
        piece = @requests.find_piece(peer, piece_index)
        cancel_piece(peer, piece) if piece
      end
    end

    private def request_piece_if_possible(peer) : Nil
      return if peer.status.choked_by_peer?
      return if @requests.pieces.size >= MAX_OPEN_REQUESTS
      return if @requests.pieces_of_peer(peer).size >= MAX_OPEN_REQUESTS_PER_PEER

      request_new_piece(peer)
      check_for_end_game
    end

    private def request_specific_piece_if_possible(peer, piece_index) : Bool
      return false if peer.status.choked_by_peer?
      return false unless peer.bitfield[piece_index]
      return false if @requests.pieces.size >= MAX_OPEN_REQUESTS
      return false if @requests.pieces_of_peer(peer).size >= MAX_OPEN_REQUESTS_PER_PEER
      return false if !@end_game_mode && @requests.find_piece(piece_index)

      request_specific_piece(peer, piece_index)
      check_for_end_game
      true
    end

    private def announce_valid_piece(peer, index, length)
      pieces_done = @requests.public_bitfield.count(true)
      pieces_total = @requests.public_bitfield.size
      @log.info "Finished download of piece #{index}"

      piece_ready.emit(peer, index, length)
      if pieces_done == pieces_total
        @status = Status::Completed
        download_completed.emit
      end
    end

    private def announce_broken_piece(peer, index, length)
      @requests.private_bitfield[index] = false
      broken_piece_received.emit(peer, index, length)
    end

    private def validate_piece(peer, index, length) : Bool
      digest = calculate_piece_hashsum(index, length)
      correct = @file.sha1_sums[index]

      digest.to_slice == correct
    end

    private def calculate_piece_hashsum(index, length)
      buffer = Bytes.new(length)
      read_piece(index, 0, buffer)
      Digest::SHA1.digest(buffer)
    end

    private def request_new_piece(peer)
      @log.info "Requesting next missing piece"
      piece_index = @piece_picker.pick_piece(peer)

      if piece_index.nil?
        @log.info "Wanted to request another piece, but all pieces have been requested at this point for this peer."
        return
      end

      request_specific_piece peer, piece_index
    end

    private def request_specific_piece(peer, piece_index)
      @log.info "Requesting piece #{piece_index} from #{peer}"

      piece = @requests.add(peer, piece_index)
      @log.debug "Sending request..."
      piece.to_a.each do |index, offset, length|
        peer.send_request(index, offset, length) # <--
      end
    rescue error
      @log.error "Failed to send request. Cancelling from request list."
      @log.error error
      @requests.cancel_piece(peer, piece) if piece
    end

    private def find_request_by_piece(peer, piece_index, offset, length)
      piece = @requests.find_piece(peer, piece_index)

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
        @requests.finalize_piece(peer, piece)
      end
    end

    private def on_peer_added(peer)
      peer.status_bit_set.on{|bit| on_status_bit_set peer, bit}
      peer.status_bit_cleared.on{|bit| on_status_bit_clear peer, bit}
      peer.piece_download_completed.on{|piece, data| on_piece_download_complete peer, piece, data}
      peer.connection_ready.on{|_peer_id| on_connection_ready peer}
      peer.have_received.on{|_piece| request_piece_if_possible peer}
      peer.bitfield_received.on{ request_piece_if_possible(peer) }
      peer.request_rejected.on{|rej| on_request_rejected peer, rej}
    end

    # Reschedules pieces of dropped peers
    private def on_peer_removed(peer)
      @requests.pieces_of_peer(peer).each do |piece|
        @requests.cancel_piece peer, piece
        reschedule_or_unpick_piece piece.index
      end
    end

    private def on_request_rejected(peer, rej)
      piece = @requests.find_piece peer, rej.index
      return if piece.nil?

      @requests.cancel_piece peer, piece
      reschedule_or_unpick_piece rej.index
    end

    private def check_for_end_game
      return if @end_game_mode
      return unless @requests.private_bitfield.all_ones?

      @end_game_mode = true
      start_end_game
    end

    # Starts the end-game mode. In this mode, all missing pieces are requested
    # from all peers having that peer (and not choking us). The first peer
    # sending us the piece "wins", and the piece is cancelled at all other
    # peers.
    private def start_end_game
      @log.info "Entering end-game mode!"
      @requests.public_bitfield.each(false) do |idx|
        @log.debug "Requesting piece #{idx} as part of the end-game"
        request_piece_from_all idx.to_u32
      end
    end

    private def request_piece_from_all(piece_index : UInt32)
      @manager.peers.each do |peer|
        request_specific_piece_if_possible peer, piece_index
      end
    end

    # Returns a random 20-characters peer id
    def self.generate_peer_id(random = Random.new)
      max = PEER_ID_CHARS.size

      random = Bytes.new(PEER_ID_LENGTH - PEER_ID_PREAMBLE.size) do
        PEER_ID_CHARS[random.rand(max)].ord.to_u8
      end

      PEER_ID_PREAMBLE + String.new(random)
    end
  end
end
