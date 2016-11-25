module Torrent
  # Holds a list of all connected peers, past peers and peer candidates.
  # Each `PeerList` is bound to up to one `Manager::Base`.
  class PeerList
    # Default maximum of concurrently connected peers
    MAX_DEFAULT_PEERS = 40

    # Maximum of candidates to hold at any time
    MAX_CANDIDATES = 1000

    record Candidate,
      transfer : Torrent::Transfer,
      address : String,
      port : UInt16,
      ranking : Int32

    # List of connected peers
    getter active_peers : Array(Client::Peer)

    # List of addresses which the peer list will never connect to.
    # Override `#blacklisted?` if you need a more complex handling than just a
    # local list of address strings.
    getter blacklist : Array(String)

    # List of peers which we may want to connect to.
    getter candidates : Deque(Candidate)

    # Maximum count of concurrently connected peers.  Note that if you set this
    # value to something less than `active_peers.size`, no peers will be
    # disconencted.  If you want this behaviour, you have to implement it
    # yourself.
    property max_peers : Int32

    # Emitted when a new candidate was added.  Note that if the candidate is
    # connected to right away, this signal will not be emitted.
    Cute.signal candidate_added(candidate : Candidate)

    # Emitted when a new peer was added
    Cute.signal peer_added(peer : Client::Peer)

    # Emitted when a peer has been removed
    Cute.signal peer_removed(peer : Client::Peer)

    def initialize(@max_peers = MAX_DEFAULT_PEERS)
      @log = Util::Logger.new("PeerList")
      @active_peers = Array(Client::Peer).new
      @blacklist = Array(String).new
      @candidates = Deque(Candidate).new
      @log.context = self
    end

    # Returns `true` if the *address* is blacklisted, meaning that no connection
    # shall be made to it.  You're free to override this method.
    def blacklisted?(address : String) : Bool
      @blacklist.includes? address
    end

    # Returns `true` if *address:port* is a known candidate.
    def candidate?(transfer : Transfer, address : String, port : UInt16) : Bool
      found = @candidates.find do |candidate|
        candidate.transfer == transfer && \
        candidate.address == address && \
        candidate.port == port
      end

      found != nil
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

    # Returns an Enumerable of all peers which use the *transfer*.
    def active_peers_of_transfer(transfer)
      @active_peers.select{|peer| peer.transfer == transfer}
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
    #
    # Note, if you're adding lots of candidates, use `#add_candidate_bulk`
    # instead to make use of the ranking mechanism.
    def add_candidate(transfer : Transfer, address : String, port : UInt16) : Bool
      added = add_candidate_bulk(transfer, address, port)
      connect_to_candidates if added
      added
    end

    # Like `#add_candidate`, but will not conenct to the peer right away if the
    # max peer count has not been reached.
    #
    # Use `#connect_to_candidates` afterwards.
    def add_candidate_bulk(transfer : Transfer, address : String, port : UInt16) : Bool
      if @candidates.size >= MAX_CANDIDATES
        @log.info "Rejecting candidate #{address} #{port}: Max candidate count reached."
        return false
      end

      ranking = check_candidate_ranking(transfer, address, port)
      return false if ranking < 1

      candidate = Candidate.new transfer, address, port, ranking
      push_candidate candidate
      true
    end

    # Connects to the most promising candidates until the peer limit has been
    # reached (or the list of candidates is empty).
    def connect_to_candidates : Nil
      Util.spawn do
        ch = Channel(Bool).new
        keep_running = true

        while keep_running
          tries = @candidates.size.clamp(0, @max_peers - @active_peers.size)
          break if tries == 0

          tries.times do
            Util.spawn{ ch.send connect_to_next_candidate }
          end

          tries.times{ keep_running &&= ch.receive }
        end
      end
    end

    private def connect_to_next_candidate
      return false if @candidates.empty?
      return false if peer_limit_reached?

      record = @candidates.shift
      connect_to_peer(record.transfer, record.address, record.port)
      true
    end

    private def check_candidate_ranking(transfer, address, port)
      return 0 if blacklisted?(address)
      return 0 if known?(transfer, address, port)

      transfer.leech_strategy.candidate_ranking(address, port)
    end

    # Pushes the *record* into the sorted (by ranking, descending) candidate
    # list.
    private def push_candidate(record)
      @log.info "Adding candidate #{record.address}:#{record.port} for transfer #{record.transfer}"

      added = false
      @candidates.each_with_index do |cand, idx|
        next if cand.ranking > record.ranking
        @candidates.insert idx + 1, record
        added = true
        break
      end

      @candidates << record unless added
      candidate_added.emit record
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
        if peer_limit_reached? # Has the limit been reached in the meantime?
          peer.close
          add_candidate_bulk(transfer, address, port)
          return false
        end

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

    private def remove_peer(peer : Client::Peer) : Nil
      @active_peers.delete peer
      peer_removed.emit peer
      connect_to_candidates
    end

    private def create_tcp_peer(transfer, address, port)
      socket = TCPSocket.new(address, port)
      Client::TcpPeer.new(transfer.manager, transfer, socket)
    rescue error
      @log.error "Failed connection to peer #{address} #{port}"
      @log.error error
      nil
    end
  end
end
