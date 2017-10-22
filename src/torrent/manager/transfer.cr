module Torrent
  module Manager
    # Manager handling a transfer of a single torrent file.
    # Will be extended in the future to handle multiple transfers at once.
    #
    # Add transfers through `#add_transfer` and call `#start!` to start them.
    # You can add transfers later too.
    class Transfer < Base
      TRACKER_CHECK_INTERVAL = 10.seconds

      # The used file manager for storage and retrieval
      getter file_manager : FileManager::Base

      # The transfers
      getter transfers : Array(Torrent::Transfer)

      # List of torrent trackers for each transfer
      getter trackers : Hash(Torrent::Transfer, Array(Client::Tracker))

      # The listen socket
      getter listen_socket : TCPServer?

      # Has the manager been started?
      getter? running : Bool = false

      def initialize(@file_manager : FileManager::Base)
        super()
        @trackers = Hash(Torrent::Transfer, Array(Client::Tracker)).new
        @transfers = Array(Torrent::Transfer).new
        @log.context = self

        @extensions.add_default_extensions(self)
      end

      # Adds *transfer* to the manager.  Returns the transfer itself.
      def add_transfer(transfer : Torrent::Transfer) : Torrent::Transfer
        @transfers << transfer

        transfer.piece_ready.on do |_peer, piece, _length|
          broadcast_have_packet(transfer, piece)
        end

        if @running
          transfer.start
          add_trackers_from_transfer transfer
          add_peers_from_trackers
        end

        transfer
      end

      # Adds a new transfer from *file*.  Returns the added `Transfer`.
      def add_transfer(file : Torrent::File)
        add_transfer Torrent::Transfer.new(
          file: file,
          manager: self,
          status: Torrent::Transfer::Status::Running,
        )
      end

      # Resumes a new transfer from *file* with *resume*.  *peer_id* is passed
      # to `Transfer`, please see it for documentation.
      # Returns the added `Transfer`.
      def add_transfer(file : Torrent::File, resume : Hash, peer_id : String | Bool = true)
        add_transfer Torrent::Transfer.new(
          resume: resume,
          file: file,
          manager: self,
          peer_id: peer_id,
        )
      end

      # Returns `true` if there's a running transfer for *info_hash*.
      def accept_info_hash?(info_hash : Bytes) : Bool
        # TODO: When transfers can be paused add checks here.
        find_transfer(info_hash) != nil
      end

      # Tries to find a transfer by *info_hash*.  Raises if not found.
      def transfer_for_info_hash(info_hash : Bytes) : Torrent::Transfer
        found = find_transfer(info_hash)

        raise Error.new("Unknown info hash #{info_hash.inspect}") if found.nil?

        found
      end

      # Tries to find a transfer by *info_hash*.  If not found, returns `nil`.
      def find_transfer(info_hash : Bytes) : Torrent::Transfer?
        @transfers.find{|t| t.info_hash == info_hash}
      end

      def port : UInt16
        if listen = @listen_socket
          listen.local_address.port.to_u16
        else
          raise Error.new("You need to call #start! before calling #port")
        end
      end

      # Starts the manager.  *bind_address* is the address to bind to.
      # *bind_port* can be an integer, or an enumerable giving integers.
      # If it's an enumerable, each port will be tried to bind to until
      # one is found that can be bound.  If no port can be bound, an error
      # will be raised.
      def start!(bind_address = "0.0.0.0", bind_port = PORT_RANGE)
        super()
        @running = true
        @listen_socket = create_tcp_server(bind_address, bind_port)
        Util.spawn{ run_accept_loop }

        @peer_list.peer_added.on do |peer|
          Util.spawn{ run_peer_loop peer }
        end

        transfers.each(&.start)
        transfers.each{|t| add_trackers_from_transfer t}

        # Add peers
        Util.spawn do
          loop do
            add_peers_from_trackers
            sleep TRACKER_CHECK_INTERVAL
          end
        end
      end

      private def create_tcp_server(bind_address, bind_port : Enumerable)
        bind_port.each do |port|
          begin
            return create_tcp_server(bind_address, port)
          rescue
            # Ignore ...
          end
        end

        raise Error.new("Not one port in #{bind_port} is available for binding on #{bind_address}")
      end

      private def create_tcp_server(bind_address, bind_port : Int)
        TCPServer.new(bind_address, bind_port)
      end

      private def run_accept_loop
        listen = @listen_socket.not_nil!
        @log.info "Accepting TCP connections on #{listen.local_address}"

        loop do
          socket = listen.accept
          peer = Client::TcpPeer.new(self, nil, socket)
          @peer_list.add_active_peer peer
        end
      end

      private def add_trackers_from_transfer(transfer)
        added = transfer.file.announce_list.map do |url|
          Client::Tracker.from_url(URI.parse url)
        end

        trackers[transfer] = added.to_a
      end

      private def add_peers_from_trackers
        @log.info "Rechecking trackers for peers where due"
        trackers.each do |transfer, clients|
          clients.each{|client| add_peer_from_tracker transfer, client}
        end
      end

      private def add_peer_from_tracker(transfer, tracker)
        return unless tracker.retry_due?

        Util.spawn do
          begin
            add_peers transfer, tracker.get_peers(transfer)
          rescue error
            @log.error "Failed to get peers from tracker #{tracker.url}"
            @log.error error
          end
        end
      end

      private def add_peers(transfer, list)
        list.each do |data|
          @peer_list.add_candidate_bulk transfer, data.address, data.port.to_u16
        end

        @peer_list.connect_to_candidates
      end

      private def broadcast_have_packet(transfer, piece)
        @log.info "Announcing ownership of piece #{piece} to peers of transfer #{transfer}"

        Util.spawn do
          @peer_list.active_peers_of_transfer(transfer).each do |remote_peer|
            begin
              remote_peer.send_have(piece)
            rescue error
              @log.error "Failed to broadcast HAVE to #{remote_peer}"
              @log.error error
            end
          end
        end
      end

      private def run_peer_loop(peer)
        loop do
          peer.run_once
        end
      rescue error
        peer.close

        @log.error "Removed peer #{peer.address} #{peer.port} due to an error"
        @log.error error
      end
    end
  end
end
