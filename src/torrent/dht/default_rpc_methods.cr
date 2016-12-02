module Torrent
  module Dht
    # Implementations of the RPC methods per BEP-0005.
    # You usually don't use this class directly, the `Dht::Manager` does it for
    # you.
    class DefaultRpcMethods
      def initialize(@manager : Manager, @dispatcher : Dispatcher, @log : Util::Logger)
        @my_id = Bencode::Any.new(Util::Gmp.export_sha1 @manager.nodes.node_id)
      end

      # Adds all default BitTorrent DHT methods
      def add_all
        add_ping
        add_find_node
        add_get_peers
        add_announce_peer
      end

      # Adds the "ping" method.  All it does is to send response containing this
      # nodes id.
      def add_ping
        @dispatcher.add "ping" do |node, query|
          @log.info "Received ping from #{node.remote_address}"
          try_initialize_node node, query
          node.send query.response({ "id" => @my_id })
        end
      end

      def add_find_node
        @dispatcher.add "find_node" do |node, query|
          try_initialize_node node, query
          target = Util::Gmp.import_sha1(query.args["target"].to_slice)
          @log.info "Received find_node from #{node.remote_address} for #{target}"
          nodes = @manager.nodes.closest_nodes(target)
          compact = NodeAddress.to_compact nodes.map(&.to_address).to_a

          node.send query.response({
            "id" => @my_id,
            "nodes" => Bencode::Any.new(compact),
          })
        end
      end

      def add_get_peers
        @dispatcher.add "get_peers" do |node, query|
          try_initialize_node node, query
          target = Util::Gmp.import_sha1 query.args["info_hash"].to_slice
          node.remote_token = token = Util::Random.bytes(4)

          response = query.response({
            "id" => @my_id,
            "token" => Bencode::Any.new(token),
          })

          if peers = @manager.peers.to_a.bsearch(&.info_hash.==(target))
            response.data["values"] = Bencode::Any.new(peers.any_sample)
          else
            nodes = @manager.nodes.closest_nodes(target)
            compact = NodeAddress.to_compact nodes.map(&.to_address).to_a
            response.data["nodes"] = Bencode::Any.new(compact)
          end

          node.send response
        end
      end

      def add_announce_peer
        @dispatcher.add "announce_peer" do |node, query|
          token = query.args["token"]?.try(&.to_slice)

          if node.remote_token != token
            @log.warn "Node #{node.remote_address} announced peer, but given token #{token.inspect} does not match #{node.remote_token.inspect}"
            node.send query.error(ErrorCode::Generic, "Wrong Token")
          else
            add_announced_peer(node, query)
            node.send query.response({ "id" => @my_id })
          end
        end
      end

      private def try_initialize_node(node, query)
        node_id = Util::Gmp.import_sha1(query.args["id"].to_slice)

        if node.id == -1 # New node?
          node.id = node_id
          @log.info "New node, id: #{node_id}"
        elsif node.id != node_id
          @log.warn "Wrong node id presented by node #{node.remote_address}"
          raise QueryHandlerError.new(201, "Wrong Id")
        end
      end

      private def add_announced_peer(node, query)
        port = query.args["port"].to_i
        implied = query.args["implied_port"]?.try(&.to_b)
        port = node.remote_address.port if implied
        info_hash = query.args["info_hash"].to_slice
        address = node.remote_address.address

        @manager.add_torrent_peer(node, info_hash, address, port.to_u16)
      end
    end
  end
end
