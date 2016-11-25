module Torrent
  module Dht
    class NodeFinder < Finder(Node)
      def query_node(node : Node, hash : BigInt) : Array(NodeAddress)?
        nodes = node.find_node(@manager.nodes.node_id, hash, timeout: 10.seconds)

        if found = nodes.find(&.id.==(hash))
          @result = @manager.create_outgoing_node(found)
        end

        nodes
      end
    end
  end
end
