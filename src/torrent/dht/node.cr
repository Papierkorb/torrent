module Torrent
  module Dht
    # Represents a torrent DHT node
    abstract class Node
      enum Health

        # The node is most likely reachable
        Good

        # The node may not be reachable anymore
        Questionable

        # Multiple attempts failed to reach the node
        Bad
      end

      # Default remote call timeout
      CALL_TIMEOUT = 30.seconds

      # Default ping timeout
      PING_TIMEOUT = 10.seconds

      # Byte size of query transactions
      TRANSACTION_LENGTH = 2

      # Node timeout.  Double this for the real timeout.
      TIMEOUT = 15.minutes

      # The node id.  This may be set to `-1` initially.
      property id : BigInt

      # Set by `#get_peers` as returned by the remote node.
      # Used by `#announce_peer`.
      getter peers_token : Bytes?

      # The token to be used by the remote node for "announce_peer" queries sent
      # to this node.
      property remote_token : Bytes?

      # The health of the node
      getter health : Health = Health::Good

      delegate good?, questionable?, bad?, to: @health

      # Emitted when the connection timed-out.
      Cute.signal connection_lost

      # Emitted when a message has been received.
      Cute.signal message_received(message : Structure::Message)

      # Emitted when a query was received.
      Cute.signal query_received(query : Structure::Query)

      # Emitted when a response was received.
      Cute.signal response_received(response : Structure::Response)

      # Emitted when an error was received.
      Cute.signal error_received(error : Structure::Error)

      # Returns the round-trip-time, which is the time span between sending a
      # ping and receiving the response.  Initially set to the max value.
      getter rtt : Time::Span = Time::Span::MaxValue

      # Returns the time the last packet has been received from this node.
      getter last_seen : Time

      def initialize(@id : BigInt)
        @log = Util::Logger.new("Node/#{@id.hash}")
        @calls = Hash(Bytes, Channel(Structure::Message?)).new
        @last_seen = Time.now
      end

      def_hash @id

      # Returns a `NodeAddress`
      def to_address : NodeAddress
        remote = remote_address
        NodeAddress.new(remote.address, remote.port, @id, !remote.family.inet?)
      end

      # Tries to add a peer at *address:port* for *info_hash*.
      def add_torrent_peer(info_hash : Bytes, address : String, port : UInt16)
      end

      # Calculates the distance to *other* from this node using the Kademlia
      # distance function: `Distance(Node, Other) = |Node.id ^ Other|`.
      def kademlia_distance(other : BigInt) : BigInt
        id ^ other
      end

      # Returns the remote host address
      def address : String
        remote_address.address
      end

      # Returns the remote port
      def port : UInt16
        remote_address.port
      end

      # Returns the remote address
      abstract def remote_address : Socket::IPAddress

      # Sends the *message* to the remote node
      abstract def send(message : Message)

      # Closes the connection (if any)
      def close
        connection_lost.emit

        connection_lost.disconnect
        query_received.disconnect
        response_received.disconnect
        error_received.disconnect
      end

      # Called by implementations to handle an incoming *datagram*
      def handle_incoming(datagram : Bytes) : Nil
        any = Bencode.load(datagram)
        message = Structure::Message.from(any)

        # Don't update @last_seen here, as the node may only be able to reach
        # us, but may be firewalled from requests by us.
        message_received.emit message
        handle_message message
      end

      # Calls a remote named *method* with *arguments*, then blocks until a
      # response has arrived or the timeout has passed.  Returns the response
      # mesage, which is either a `Structure::Response` or `Structure::Error` or
      # `nil` if the timeout was triggered.
      #
      # The `last_seen` property is updated for responses and error responses,
      # but not on timeout.
      def remote_call?(method : String, arguments : Bencode::Any::AnyHash, timeout = CALL_TIMEOUT)
        transaction = generate_unique_transaction
        query = Structure::Query.new(transaction, method, arguments)

        ch = Channel(Structure::Message?).new
        @calls[transaction] = ch

        send query

        result = wait_on_channel ch, timeout
        @calls.delete transaction
        update_health result.nil?
        learn_or_reject_node(result) if result.is_a?(Structure::Response)
        @last_seen = Time.now if result
        result
      end

      # Like `#remote_call?`, but raises a `Dht::CallError` sub-class on any
      # error.  Else, the result `Bencode::Any::AnyHash` is returned.
      def remote_call(method : String, arguments : Bencode::Any::AnyHash, timeout = CALL_TIMEOUT)
        result = remote_call?(method, arguments, timeout)

        if result.nil?
          raise CallTimeout.new("No response to #{method.inspect} after #{timeout}")
        elsif result.is_a?(Structure::Error)
          raise RemoteCallError.new(method, result)
        end

        result.as(Structure::Response).data
      end

      # Sends a "ping" query to the remote node, giving our nodes id.
      # This is a blocking method, which either returns the remote nodes id,
      # or `nil` if it did not respond.  This method may raise, but will
      # **not** raise on 1) error responses and 2) timeouts.
      #
      # The `last_seen` property is only updated if a successful response was
      # received.
      def ping(this_nodes_id : BigInt | Bytes, timeout = PING_TIMEOUT) : BigInt?
        id = convert_node_id this_nodes_id

        start = Time.now
        old_seen = @last_seen
        result = remote_call?("ping", { "id" => Bencode::Any.new(id) }, timeout)
        @rtt = Time.now - start
        @log.info "Node responded to ping after #{@rtt}"

        if result.is_a?(Structure::Response)
          Util::Gmp.import_sha1 result.data["id"].to_slice
        else
          @last_seen = old_seen
          nil
        end
      end

      # Sends a "find_node" query to the remote node to find the *target* node.
      # Raises on any error.
      def find_node(this_nodes_id : BigInt | Bytes, target : BigInt | Bytes, timeout = CALL_TIMEOUT) : Array(NodeAddress)
        id = convert_node_id this_nodes_id
        dest = convert_node_id target

        result = remote_call("find_node", {
          "id" => Bencode::Any.new(id),
          "target" => Bencode::Any.new(dest),
        }, timeout: timeout)

        compact = result["nodes"].to_slice
        NodeAddress.from_compact compact
      end

      # Sends a "get_peers" query to the remote node to find
      # 1) DHT nodes possibly with knowledge of peers for the torrent
      # 2) or to find torrent peers
      #
      # Usually, only one of the two is returned, but a DHT node could return
      # values for both anyway.  Raises if the invocation fails.
      def get_peers(this_nodes_id : BigInt | Bytes, info_hash : BigInt | Bytes, timeout = CALL_TIMEOUT) : Tuple(Array(NodeAddress), Array(Torrent::Structure::PeerInfo))
        id = convert_node_id this_nodes_id
        result = remote_call("get_peers", {
          "id" => Bencode::Any.new(id),
          "info_hash" => Bencode::Any.new(convert_node_id(info_hash)),
        }, timeout: timeout)

        nodes = Array(NodeAddress).new
        if compact = result["nodes"]?
          nodes = NodeAddress.from_compact compact.to_slice
        end

        peers = Array(Torrent::Structure::PeerInfo).new
        if values = result["values"]?
          peers = values.to_a.map do |value|
            Torrent::Structure::PeerInfoConverter.from_bytes(value.to_slice)
          end.to_a
        end

        if token = result["token"]?
          @peers_token = token.to_slice
        end

        { nodes, peers }
      end

      # Sends a "announce_peer" query to tell it that this torrent peer is now
      # participating in the swarm for *info_hash*.  It's important to call
      # `#get_peers` beforehand to acquire a peer token from the remote node.
      #
      # The *port* is the port this peer is listening on.
      def announce_peer(this_nodes_id : BigInt | Bytes, info_hash : BigInt | Bytes, port : Int, timeout = CALL_TIMEOUT) : Nil
        token = @peers_token
        raise Error.new("No peers_token present, call #get_peers") if token.nil?

        result = remote_call("announce_peer", {
          "id" => Bencode::Any.new(convert_node_id this_nodes_id),
          "info_hash" => Bencode::Any.new(convert_node_id(info_hash)),
          "implied_port" => Bencode::Any.new(0),
          "port" => Bencode::Any.new(port.to_i32),
          "token" => Bencode::Any.new(token),
        }, timeout: timeout)

        nil
      end

      # Pings the remote node if the node hasn't been seen for `TIMEOUT`.
      # Returns `true` if the node hasn't gone to bad health, returns `false`
      # if the health is or has gone bad.
      #
      # If the remote node responds with the wrong node id, the health will be
      # set to `Health::Bad` and `false` is returned.
      #
      # The *timeout* is used as the `#ping` timeout.
      def refresh_if_needed(this_nodes_id, timeout = PING_TIMEOUT) : Bool
        return false if @health.bad?
        return true if Time.now < @last_seen + TIMEOUT

        ping(this_nodes_id, timeout: timeout)

        # Force last_seen update to give the node time to recover
        @last_seen = Time.now
        !@health.bad?
      rescue
        @health = Health::Bad
        false
      end

      def to_s(io)
        io.print "<Dht::Node #{remote_address} / "

        if @id == -1
          io.print "UNKNOWN"
        else
          io.print Util::Gmp.export_sha1(@id).hexstring
        end

        io.print ">"
      end

      {% for op in %i[ < > <= >= <=> ] %}
        def {{ op.id }}(other : Node)
          @id {{ op.id }} other.id
        end
      {% end %}

      private def convert_node_id(id : Bytes) : Bytes
        raise ArgumentError.new("id must be 20 bytes in size") if id.size != 20
        id
      end

      private def convert_node_id(id : BigInt) : Bytes
        Util::Gmp.export_sha1 id
      end

      private def generate_unique_transaction : Bytes
        size = TRANSACTION_LENGTH

        loop do
          tr = generate_transaction(size)
          return tr unless @calls.includes?(tr)
          size += 1
        end
      end

      private def generate_transaction(length) : Bytes
        Bytes.new(length) do
          Random::DEFAULT.rand(0..0xFF).to_u8
        end
      end

      private def handle_message(query : Structure::Query)
        query_received.emit query
      end

      private def handle_message(response : Structure::Response)
        response_received.emit response
        notify_channel response
      end

      private def handle_message(error : Structure::Error)
        error_received.emit error
        notify_channel error
      end

      private def notify_channel(response)
        channel = @calls[response.transaction]?

        if channel.nil?
          @log.warn "Received response with unknown transaction #{response.transaction.hexstring}"
        else
          channel.send response
        end
      end

      private def wait_on_channel(channel, timeout)
        spawn do
          sleep timeout
          channel.send nil
        end

        result = channel.receive
      end

      private def learn_or_reject_node(response)
        id = response.data["id"]?
        return unless id

        sent_id = Util::Gmp.import_sha1 id.to_slice
        if @id == -1
          @id = sent_id
        elsif @id != sent_id
          raise CallError.new("Sent id #{sent_id} does not match previous id #{@id}")
        end
      end

      private def update_health(failure)
        if failure == false
          @health = Health::Good
        elsif @health.good?
          @health = Health::Questionable
        elsif @health.questionable?
          @health = Health::Bad
        end
      end
    end
  end
end
