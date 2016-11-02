module Torrent
  # Holds a list of all connected peers, past peers and peer candidates.
  # Each `PeerList` is bound to up to one `Manager::Base`.
  class PeerList
    # Default maximum of concurrently connected peers
    MAX_DEFAULT_PEERS = 40

    # List of connected peers
    getter active_peers : Array(Client::Peer)

    # List of past peers. Tuples contain the address as first, the port as
    # second and the peer-id as third element.  The peer-id may be `nil` if
    # the peer didn't send us one, e.g. because the connect itself failed.
    getter past_peers : Array(Tuple(String, UInt16, Bytes?))

    # List of addresses which the peer list will never connect to.
    # Override `#blacklisted?` if you need a more complex handling than just a
    # local list of address strings.
    getter blacklist : Array(Tuple(String))

    # List of peers which we may want to connect to.
    getter candidates : Deque(Tuple(Transfer, String, UInt16))

    # Maximum count of concurrently connected peers.  Note that if you set this
    # value to something less than `active_peers.size`, no peers will be
    # disconencted.  If you want this behaviour, you have to implement it
    # yourself.
    property max_peers : Int32

    # Emitted when a new candidate was added.  Note that if the candidate is
    # connected to right away, this signal will not be emitted.
    Cute.signal candidate_added(transfer : Transfer, address : String, port : UInt16)

    # Emitted when a new peer was added
    Cute.signal peer_added(peer : Client::Peer)

    # Emitted when a peer has been removed
    Cute.signal peer_removed(peer : Client::Peer)

    def initialize(@max_peers = MAX_DEFAULT_PEERS)
      @log = Util::Logger.new("PeerList")
      @active_peers = Array(Client::Peer).new
      @past_peers = Array(Tuple(String, UInt16, Bytes?)).new
      @blacklist = Array(Tuple(String)).new
      @candidates = Deque(Tuple(Transfer, String, UInt16)).new
      @log.context = self
    end

    # Returns `true` if the *address* is blacklisted, meaning that no connection
    # shall be made to it.  You're free to override this method.
    def blacklisted?(address : String) : Bool
      @blacklist.includes? address
    end

    # Returns `true` if *address:port* is a known candidate.
    def candidate?(transfer : Transfer, address : String, port : UInt16) : Bool
      @candidates.includes?({ transfer, address, port })
    end

    # Returns `true` if *address:port* is a currently connected-to peer.
    def connected_to?(transfer : Transfer, address : String, port : UInt16) : Bool
      find_peer(transfer, address, port) != nil
    end

    # Returns the active peer *address:port* if any.
    def find_peer(transfer : Transfer, address : String, port : UInt16) : Client::Peer?
      @active_peers.find do |peer|
        begin
          peer.transfer == transfer && \
          peer.address == address && \
          peer.port == port
        rescue
          false
        end
      end
    end

    # Returns `true` if *address:port* is a known candidate OR if it's a
    # connected peer.
    def known?(transfer : Transfer, address : String, port : UInt16) : Bool
      connected_to?(transfer, address, port) || candidate?(transfer, address, port)
    end

    # Returns `true` if the maximum count of active peers has been reached.
    def peer_limit_reached? : Bool
      @active_peers.size >= @max_peers
    end

    # Adds a candidate to the peer list. It may be connected to right away if
    # the maximum count of peers has not been reached, or later.
    #
    # Returns `true` if the candidate was added, or `false` if the candidate
    # is already known or if it's blacklisted.
    def add_candidate(transfer : Transfer, address : String, port : UInt16) : Bool
      return false if blacklisted?(address)
      return false if known?(transfer, address, port)

      if @active_peers.size < @max_peers
        Util.spawn{ connect_to_peer(transfer, address, port) }
      else
        @log.info "Adding candidate #{address}:#{port} for transfer #{transfer}"
        @candidates << { transfer, address, port }
        candidate_added.emit transfer, address, port
      end

      true
    end

    # Connects to the given peer right away.  This circumvents the candidate
    # list, **circumvents the blacklist**, and also doesn't care about the
    # maximum peer count.
    #
    # Returns `true` on success, or `false` if the connection failed.
    #
    # This is a blocking call. See also `#can_connect_to?`.
    def connect_to_peer(transfer : Transfer, address : String, port : UInt16) : Bool
      @log.info "Connecting to #{address}:#{port} for transfer #{transfer}"
      if peer = create_tcp_peer(transfer, address, port)
        add_peer peer
        peer.send_handshake
        true
      else
        false
      end
    end

    # Adds *peer* to the list of active peers. Does a blacklist check, and will
    # `Client::Peer#close` the connection if it's a unwanted connection.
    # Will also close the connection if the maximum count of active peers is
    # already reached, or if we're already connected to that peer for the same
    # transfer.
    def add_active_peer(peer : Client::Peer) : Bool
      if blacklisted?(peer.address)
        peer.close
        @log.info "Closed incoming connection from blacklisted address #{peer.address}"

        false
      elsif @active_peers.size >= @max_peers
        peer.close
        @log.info "Closed incoming connection #{peer.address}:#{peer.port} as the peer limit is already reached"

        false
      elsif connected_to?(peer.transfer, peer.address, peer.port)
        peer.close
        @log.info "Closed incoming connection #{peer.address}:#{peer.port} as we're already connected to that peer"

        false
      else
        add_peer peer
        true
      end
    end

    # Checks if a connection to the given *address:port* should be made.  This
    # checks for the maximum peer count, and makes sure that the address is not
    # blacklisted.
    def can_connect_to?(address : String, port : UInt16) : Bool
      @active_peers.size < @max_peers && !blacklisted?(address, port)
    end

    private def add_peer(peer)
      @active_peers << peer
      peer_added.emit peer

      peer.connection_lost.on{ remove_peer peer }
    end

    private def remove_peer(peer : Client::Peer)
      @active_peers.delete peer
      peer_removed.emit peer
      Util.spawn{ connect_to_next_candidate }
    end

    private def connect_to_next_candidate
      while !@candidates.empty? && !peer_limit_reached?
        transfer, address, port = @candidates.shift
        next if blacklisted?(address)

        connect_to_peer(transfer, address, port)
      end
    end

    private def create_tcp_peer(transfer, address, port)
      socket = TCPSocket.new(address, port)
      Client::TcpPeer.new(transfer, socket)
    rescue error
      @log.error "Failed connection to peer #{address} #{port}"
      @log.error error
      nil
    end
  end
end
