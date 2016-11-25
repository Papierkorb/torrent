module Torrent
  module Dht
    class NodeList

      # Ping a node after this time and remove it if it doesn't respond
      NODE_TIMEOUT = 15.minutes

      # Ping each node in a bucket after this time
      BUCKET_REFRESH_INTERVAL = 15.minutes

      # Range of valid node ids.
      NODE_ID_RANGE = 0.to_big_i...2.to_big_i**160

      # Initial count of buckets
      INITIAL_CAPACITY = 1

      # Emitted when a node was added to the list
      Cute.signal node_added(node : Node)

      # Emitted when a node was removed from the list
      Cute.signal node_removed(node : Node)

      # Emitted when a node has been rejected.
      Cute.signal node_rejected(node : Node)

      # Buckets in the node list
      getter buckets : Array(Bucket)

      # Id of this peer
      getter node_id : BigInt

      # The *node_id* is this nodes id, and must be in range of `NODE_ID_RANGE`.
      def initialize(node_id : Int)
        @node_id = node_id.to_big_i

        unless NODE_ID_RANGE.includes? @node_id
          raise ArgumentError.new("Given node id is out of range")
        end

        @buckets = Array(Bucket).new(INITIAL_CAPACITY)
        @buckets << Bucket.new(NODE_ID_RANGE)
      end

      # Returns `true` if the list knows of a node *node_id*.
      def includes?(node_id : BigInt)
        find_bucket(node_id).includes?(node_id)
      end

      # Returns `true` if the list knows of the *node* by its id.
      def includes?(node : Node)
        find_bucket(node.id).includes?(node.id)
      end

      # Tries to add *node*.  *node* must be fully initialized.  Returns `true`
      # if the node was accepted, else `false` is returned.  If the node is
      # already known, `false` is returned.
      def try_add(node : Node) : Bool
        bucket = find_bucket(node.id)

        if bucket.includes?(node)
          node_rejected.emit node
          return false
        end

        if bucket.full?
          bucket = try_split(bucket, node.id)
          if bucket.nil?
            node_rejected.emit node
            return false
          end
        end

        bucket.add node
        node_added.emit(node)
        true
      end

      # Checks if a node with *node_id* would be accepted or flat out be
      # rejected.
      def would_accept?(node_id : BigInt) : Bool
        bucket = find_bucket(node_id)
        return false if bucket.includes?(node_id)

        if bucket.full?
          do_split?(bucket, node_id)
        else
          true
        end
      end

      private def do_split?(bucket, node_id : BigInt) : Bool
        return false unless bucket.covers?(@node_id)
        return false unless bucket.splittable?
        return false unless bucket.should_split?(node_id)
        true
      end

      private def try_split(bucket, node_id) : Bucket?
        return nil unless do_split? bucket, node_id
        left, right = do_split(bucket, node_id)
        left.covers?(node_id) ? left : right
      end

      private def do_split(bucket, node_id) : Tuple(Bucket, Bucket)
        left, right = bucket.split
        idx = @buckets.index(bucket)

        raise IndexError.new("#do_split is broken") if idx.nil?
        @buckets[idx] = right
        @buckets.insert(idx, left)
        { left, right }
      end

      # Returns the `Node` if found, else `nil` is returned.
      def find_node(remote : Socket::IPAddress) : Node?
        @buckets.each do |bucket|
          bucket.nodes.each do |node|
            return node if node.remote_address == remote
          end
        end

        nil
      end

      # Returns the `Node` if found.
      def find_node(node_id : BigInt) : Node?
        find_bucket(node_id).find_node(node_id)
      end

      # Removes the *node* from the list
      def delete(node : Node)
        id = node.id
        return if id < 0

        find_bucket(id).delete(node)
      end

      # Returns the count of all nodes in the list.
      def count
        @buckets.map(&.node_count).sum
      end

      # Returns the `Bucket` which is responsible for *id*.  This does not mean
      # a node is known by this *id*.  Only fails with an `IndexError` if the
      # *id* falls outside the legal range.
      def find_bucket(id : BigInt) : Bucket
        raise IndexError.new("Node id is out of range: #{id.inspect}") unless NODE_ID_RANGE.includes?(id)
        # @buckets.bsearch{|bucket| bucket.covers? id}.not_nil!
        @buckets.find{|bucket| bucket.covers? id}.not_nil!
      end

      # Returns an array of nodes near *hash*.  The distance function is the
      # one defined by Kademlia: `distance(A,B) = |A xor B|`, where **A** is the
      # hash and **B** is the currently compared nodes id.
      def closest_nodes(hash : BigInt, count = Bucket::MAX_NODES) : Array(Node)
        list = Util::KademliaList(Node).new(hash, count)
        each_node{|node| list << node}
        list.to_a
      end

      # Refreshes all buckets
      def refresh_buckets
        # TODO
      end

      # Yields each `Node` in the node list.
      def each_node : Nil
        @buckets.each do |bucket|
          bucket.nodes.each{|node| yield node}
        end
      end

      # Yields each `Node` with the `Bucket` it is in as second argument.
      def each_node_with_bucket : Nil
        @buckets.each do |bucket|
          bucket.nodes.each{|node| yield node, bucket}
        end
      end

      # Helper method which prints a readable dump of all buckets and nodes
      # inside it.  The block is called for every output line.
      def debug_dump(&block : String -> Nil)
        block.call "-- Node list dump --"
        block.call " This nodes id: #{Util::Gmp.export_sha1(node_id).hexstring}"
        block.call " #{count} Nodes in #{@buckets.size} Buckets:"

        @buckets.each do |bucket|
          block.call "  - #{bucket.node_count} / #{Bucket::MAX_NODES}: #{bucket.range} #{"(self)" if bucket.covers? @node_id}"
          bucket.nodes.each do |node|
            block.call "    + #{node.remote_address} => #{Util::Gmp.export_sha1(node.id).hexstring} [#{node.rtt}]"
          end
        end

        block.call "--    Dump end    --"
      end
    end
  end
end
