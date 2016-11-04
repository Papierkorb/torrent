module Torrent
  module Manager
    # Manager handling a transfer of a single torrent file.
    # Will be extended in the future to handle multiple transfers at once.
    #
    # Call `#start!` to start the transfer(s).
    class Transfer < Base
      TRACKER_CHECK_INTERVAL = 10.seconds

      # The .torrent file to transfer
      getter file : Torrent::File

      # The used file manager for storage and retrieval
      getter file_manager : FileManager::Base

      # The transfer descriptor
      getter transfer : Torrent::Transfer do
        Torrent::Transfer.new(
          file: @file,
          manager: self,
          status: Torrent::Transfer::Status::Running,
        )
      end

      getter listen_socket : TCPServer?

      def initialize(@file : Torrent::File, @file_manager : FileManager::Base)
        super()
        @log.context = self

        Cute.connect transfer.piece_ready, broadcast_have_packet(_peer, piece, _length)

        @extensions.add_default_extensions(self)
      end

      def accept_info_hash?(info_hash : Bytes) : Bool
        info_hash == transfer.info_hash
      end

      def transfer_for_info_hash(info_hash : Bytes) : Torrent::Transfer
        raise Error.new("Unknown info hash #{info_hash.inspect}") if info_hash != transfer.info_hash
        transfer
      end

      def port
        if listen = @listen_socket
          listen.local_address.port
        else
          raise Error.new("You need to call #start! before calling #port")
        end
      end

      # Starts the manager. *bind_address* is the address to bind to.
      # *bind_port* can be an integer, or an enumerable giving integers.
      # If it's an enumerable, each port will be tried to bind to until
      # one is found that can be bound. If no port can be bound, an error
      # will be raised.
      def start!(bind_address = "0.0.0.0", bind_port = PORT_RANGE)
        super()
        @listen_socket = create_tcp_server(bind_address, bind_port)
        Util.spawn{ run_accept_loop }

        @peer_list.peer_added.on do |peer|
          Util.spawn{ run_peer_loop peer }
        end

        add_trackers_from_file

        transfer.start

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
          peer = Client::TcpPeer.new(transfer, socket)
          @peer_list.add_active_peer peer
        end
      end

      private def add_trackers_from_file
        added = @file.announce_list.map do |url|
          Client::Tracker.from_url(URI.parse url)
        end

        trackers.concat added
      end

      private def add_peers_from_trackers
        @log.info "Rechecking trackers for peers where due"
        trackers.each do |client|
          add_peer_from_tracker client
        end
      end

      private def add_peer_from_tracker(tracker)
        add_peers tracker.get_peers(transfer) if tracker.retry_due?
      rescue error
        @log.error "Failed to get peers from tracker #{tracker.url}"
        @log.error error
      end

      private def add_peers(list)
        list.each do |data|
          @peer_list.add_candidate_bulk transfer, data.address, data.port.to_u16
        end

        @peer_list.connect_to_candidates
      end

      private def broadcast_have_packet(_peer, piece, _length)
        @log.info "Announcing ownership of piece #{piece} to peers"

        Util.spawn do
          peers.each do |remote_peer|
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
