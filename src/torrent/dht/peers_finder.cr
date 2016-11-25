module Torrent
  module Dht
    class PeersFinder < Finder(Tuple(Array(Node), Array(Torrent::Structure::PeerInfo)))
      def query_node(node : Node, hash : BigInt) : Array(NodeAddress)?
        nodes, peers = node.get_peers(@manager.nodes.node_id, hash)

        unless peers.empty?
          if @result.nil?
            @result = { [ node ], peers }
          else
            old = @result
            @result = { old[0] << node, old[1] + peers }
          end
        end

        nodes
      end
    end
  end
end
