module Torrent
  module Dht
    # Manager of the local DHT node.  Can be used independently of the Torrent
    # non-DHT parts.
    class Manager
      PORT_RANGE = Torrent::Manager::Base::PORT_RANGE

      # Max amount of different info hashes to keep at once.
      MAX_INFO_HASHES = 200

      DEFAULT_BOOSTRAP_NODES = [
        { "router.bittorrent.com", 6881u16 },
        { "router.utorrent.com", 6881u16 },
        # { "router.transmissionbt.org", 6881u16 },
      ]

      # Emitted when bootstrapping started.
      Cute.signal bootstrap_started

      # Emitted when bootstrapping has finished.
      Cute.signal bootstrap_finished

      # Emitted when a peer has announced itself to us.  Nodes will do this
      # periodically as keep-alive mechanism.
      Cute.signal peer_added(node : Node, info_hash : Bytes, address : String, port : UInt16)

      # The DHT node list
      getter nodes : NodeList

      # The bootstrap nodes to use.  Initialized by a default list of bootstrap
      # nodes.  Modify this list before calling `#start`.  The manager will
      # connect to **all** nodes at once.
      property bootstrap_nodes : Array(Tuple(String, UInt16))

      # The method dispatcher
      property dispatcher : Dispatcher

      # Stored peers as were announced by `announce_peer` queries.  Uses a
      # `Util::KademliaList`, so that we prefer info hashes nearer to our node
      # id.
      getter peers : Util::KademliaList(PeerList)

      @port : UInt16?

      def initialize(this_nodes_id : BigInt? = nil)
        @log = Util::Logger.new("Dht/Manager")
        @nodes = NodeList.new(this_nodes_id || Manager.generate_node_id)
        @dispatcher = Dispatcher.new
        @socket = Util::UdpSocket.new
        @bootstrap_nodes = DEFAULT_BOOSTRAP_NODES.dup
        @peers = Util::KademliaList(PeerList).new(@nodes.node_id, MAX_INFO_HASHES)

        @log.debug "This nodes id is #{@nodes.node_id}"

        DefaultRpcMethods.new(self, @dispatcher, @log).add_all
      end

      # Adds a torrent peer to the list of peers.  Used by the "announce_peer"
      # RPC query.
      def add_torrent_peer(node : Node, info_hash : Bytes, address : String, port : UInt16)
        id = Util::Gmp.import_sha1 info_hash
        list = @peers.to_a.find{|list| list.info_hash == id}
        list = PeerList.new(id) if list.nil?

        peer_added.emit node, info_hash, address, port
        list.add(address, port)

        peers << list
      end

      # Adds a node at *address* on *port*.  Raises on timeout or if the remote
      # peer sends garbage data.  Returns `nil` if the target bucket in the
      # node list is full.  Returns the `Node` otherwise.
      def add_node(address, port) : Node?
        @log.info "Adding node at #{address}:#{port}"
        node = create_outgoing_node(address, port)
        remote_node_id = node.ping(@nodes.node_id)

        if remote_node_id.nil?
          raise Error.new("Failed to connect to #{address}:#{port} - Timeout")
        end

        node.id = remote_node_id
        return nil unless @nodes.try_add(node)
        init_node node
        node
      end

      # Convenience method, see the other `#add_node`.
      def add_node(address : NodeAddress) : Node?
        add_node(address.address, address.port) if address.id != @nodes.node_id
      end

      # Returns the listening port.  Raises if the manager has not been
      # `#start`ed yet.
      def port : UInt16
        if num = @port
          num
        else
          raise Error.new("Manager has not been #start'ed yet.")
        end
      end

      # Starts listening on an UDP port.
      def start(bind_address = "0.0.0.0", bind_port = PORT_RANGE)
        @port = bind_socket bind_address, bind_port

        Util.spawn("DHT-UDP"){ handle_incoming }
        connect_to_bootstrap_nodes

        Util.spawn("Peer+NodeList management") do
          while @port
            @peers.each{|list| list.check_timeouts}
            sleep 1.minute
          end
        end
      end

      # Stops listening
      def stop
        @socket.close
        @port = nil
      end

      # Adds all nodes by address from *list*.  Skips those which would've been
      # rejected anyway before attempting a connection.
      def add_all(list : Iterable(NodeAddress))
        accepted = list.count do |addr|
          if @nodes.would_accept?(addr.id)
            Util.spawn("Add #{addr.inspect}", fatal: false){ add_node addr }
            true
          end
        end

        @log.debug "Trying to connect to #{accepted} of #{list.size} nodes"
      end

      # Tries to find a specific `Node` by its *node_id*.  Returns the node if
      # it is found, else returns `nil`.  This method is blocking and might take
      # a while to complete.
      def find_node(node_id : BigInt) : Node?
        @nodes.find_node(node_id) || NodeFinder.new(self).run(node_id)
      end

      # Tries to find a `Node` by its *address*.  If we don't know such a
      # node, a new `Node` is created to point at the *address* and returned.
      #
      # If *ping* is `true`, the remote node will be pinged with a short
      # timeout.  If it fails to respond, `nil` is returned.  Else it is put
      # into the routing table if it fits in there.
      #
      # If *ping* is `false`, the remote node will **not** be pinged, nor
      # will it be put into the routing table.
      #
      # This method blocks only if *ping* is `true`.
      def find_or_connect_node(address : NodeAddress, ping = true) : Node?
        node = @nodes.find_node(address.id)
        return node if node

        node = create_outgoing_node(address)
        return node unless ping

        if node.ping(@nodes.node_id, 10.seconds).nil?
          node.close
          nil
        else
          @nodes.try_add node
          node
        end
      end

      # Tries to find peers for a *info_hash* in the DHT.  If peers are found,
      # returns a list of nodes (to announce to) and the peer list itself.
      def find_peers(info_hash : BigInt) : Tuple(Array(Node), Array(Torrent::Structure::PeerInfo))?
        PeersFinder.new(self).run(info_hash)
      end

      private def connect_to_bootstrap_nodes
        ch = Channel(Nil).new
        count = @bootstrap_nodes.size

        bootstrap_started.emit
        @bootstrap_nodes.each do |address, port|
          Util.spawn(name: "Connect #{address}:#{port}") do
            begin
              connect_to_bootstrap_node address, port
            ensure
              ch.send nil
            end
          end
        end

        Util.spawn("Self finder") do
          count.times{ ch.receive }
          @log.info "Looking for more near nodes."
          find_node(@nodes.node_id)
          @log.info "Initial node search done, node count: #{@nodes.count}"
          bootstrap_finished.emit
        end
      end

      private def connect_to_bootstrap_node(address, port)
        add_node(address, port)
      rescue error
        @log.error "Failed to connect to bootstrap node #{address}:#{port}"
        @log.error error
      end

      private def bind_socket(address, ports : Enumerable)
        used = ports.find do |port|
          begin
            @socket.bind address, port.to_u16
            true
          rescue
            false
          end
        end

        raise Error.new("No free port found in #{ports.inspect}") if used.nil?
        used.to_u16
      end

      private def handle_next_incoming
        buf = Bytes.new(Util::UdpSocket::MTU)
        bytes, remote = @socket.receive buf

        dispatch_datagram buf[0, bytes], remote if bytes > 0
      end

      private def handle_incoming
        while @port
          handle_next_incoming
        end
      end

      private def dispatch_datagram(datagram, remote)
        node = @nodes.find_node(remote)
        new_node = node.nil?

        if node.nil?
          node = create_incoming_node(remote)
          init_node node
        end

        node.handle_incoming(datagram)
        add_new_node(node) if new_node
      end

      private def add_new_node(node : Node)
        if node.id == -1
          @log.warn "Received stray datagram from unknown node #{node.remote_address}"
        else
          node.close unless @nodes.try_add node
        end
      end

      private def init_node(node)
        node.connection_lost.on do
          @log.info "Lost connection to node #{node.remote_address}"
          @nodes.delete node
        end

        node.query_received.on do |query|
          @dispatcher.remote_invocation node, query
        end
      end

      protected def create_incoming_node(remote) : Node
        UdpNode.new(@socket, remote, owns_socket: false)
      end

      # Creates a new node and returns it **without** adding it to the node
      # list.
      def create_outgoing_node(address : NodeAddress) : Node
        create_outgoing_node address.address, address.port
      end

      # ditto
      def create_outgoing_node(address : String, port : UInt16) : Node
        socket = Util::UdpSocket.new
        socket.connect(address, port)
        UdpNode.new(socket, socket.remote_address, owns_socket: true)
      end

      # Generates a random node id
      def self.generate_node_id(random = Random::DEFAULT) : BigInt
        Util::Gmp.import_sha1 Util::Random.bytes(Util::Gmp::SHA1_LEN)
      end
    end
  end
end
