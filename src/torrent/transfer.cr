module Torrent
  # Stores data about a single torrent transfer
  class Transfer
    PEER_ID_LENGTH = 20
    PEER_ID_PREAMBLE = "-CR0001-"
    PEER_ID_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    # Maximum count of open piece requests to download pieces *from* peers
    MAX_OPEN_REQUESTS = 100

    # Max count of open piece requests to download pieces from a single peer
    MAX_OPEN_REQUESTS_PER_PEER = 4

    # Cancel a piece request after some time if it's still running.
    PIECE_TIMEOUT = 1.minute

    #
    PIECE_CHECK_INTERVAL = 10.seconds

    # Transfer states
    enum Status

      # The transfer has stopped. Initial status.
      Stopped = 3

      # The transfer is currently running.
      Running = 2

      # The transfer has completed.
      Completed = 1
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

    # Manages piece requests
    getter requests : Util::RequestList

    # The used piece picker
    property piece_picker : PiecePicker::Base

    # The used leech strategy
    property leech_strategy : LeechStrategy::Base

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

      @leech_strategy = LeechStrategy::Default.new
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

      @leech_strategy.start(self)
    end

    # Changes the transfer status.
    def change_status(new_status)
      return if @status == new_status

      @status = new_status
      status_changed.emit new_status

      if @status == Status::Completed
        download_completed.emit
      end
    end

    private def on_connection_ready(peer)
      peer.send_bitfield(@requests.public_bitfield)
      peer.express_interest if left > 0
      peer.unchoke_peer
    end

    private def on_peer_added(peer)
      peer.connection_ready.on{|_peer_id| on_connection_ready peer}

      @leech_strategy.peer_added(peer)
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
