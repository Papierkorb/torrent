module Torrent
  module Dht
    # Contains known nodes
    class Bucket

      # Max nodes per bucket
      MAX_NODES = 8

      # Range of the smallest possible bucket
      SMALLEST_BUCKET = MAX_NODES

      # Range of nodes this bucket accepts
      property range : Range(BigInt, BigInt)

      # Time of the last bucket refresh
      property last_refresh : Time

      # Nodes in this bucket.  Do not write to this directly.
      getter nodes : Array(Node)

      def initialize(@range)
        @nodes = Array(Node).new(MAX_NODES)
        @last_refresh = Time.now
      end

      protected def initialize(@range, @nodes, @last_refresh)
      end

      # Count of nodes in the bucket
      def node_count
        @nodes.size
      end

      # Is the bucket full?
      def full?
        @nodes.size >= MAX_NODES
      end

      # Returns `true` if *node* is a known node
      def includes?(node : Node) : Bool
        includes? node.id
      end

      # Returns `true` if *id* is a known node in the bucket.
      def includes?(id : BigInt)
        !find_node(id).nil?
      end

      # Finds a node by *id*
      def find_node(id : BigInt) : Node?
        @nodes.find{|node| node.id == id}
      end

      # Returns `true` if this bucket can be split
      def splittable? : Bool
        (range.end - range.begin) > SMALLEST_BUCKET
      end

      # Splits this bucket into two new ones.
      def split : Tuple(Bucket, Bucket)
        left = Array(Node).new(MAX_NODES)
        right = Array(Node).new(MAX_NODES)

        middle = calculate_middle
        l_range = range.begin...middle
        r_range = middle...range.end

        @nodes.each do |node| # Redistribute our nodes
          next if node.nil?
          if node.id > middle
            right << node
          else
            left << node
          end
        end

        { Bucket.new(l_range, left, @last_refresh), Bucket.new(r_range, right, @last_refresh) }
      end

      delegate covers?, :begin, :end, to: @range

      # Adds *node* into the bucket.  Raises if the bucket is full.
      def add(node : Node)
        raise ArgumentError.new("Bucket is full") if full?
        raise IndexError.new("Node id not in bucket range") unless covers?(node.id)

        unless @nodes.includes?(node)
          @nodes << node
          @nodes.sort!
        end
      end

      # Removes *node* from the bucket.
      def delete(node : Node)
        @nodes.delete node
      end

      # Checks if a node *id* were added to the bucket, if it could split to
      # make space for it.  Does not do the `#splittable?` and `#full?` checks!
      #
      # A split does not make sense if the bucket has only nodes in the left
      # or right side of it and the added node would fall into the same,
      # assuming that this bucket is currently full.
      #
      # **Note:** You still have to make sure that this processes node id lies
      # inside this bucket.  Else, a split never occurs.
      def should_split?(id : BigInt)
        middle = calculate_middle

        if id <= middle
          !@nodes.all?{|node| node && node.id <= middle}
        else
          !@nodes.all?{|node| node && node.id > middle}
        end
      end

      # Refreshes the bucket.  This means that all nodes, which we've not seen
      # for 15 minutes, will be pinged.  If they respond everything is fine.
      # If they do not, their health will worsen.  If their health goes
      # `Node::Health::Bad`, the node will be evicted from the bucket.
      #
      # This basically means that an unhealthy node is given two chances over
      # a period of 15 minutes to stabilize again.
      #
      # If however the "ping" invocation raises an error the node will be
      # evicted right away.  This happens if the node changed its node id.
      def refresh(this_nodes_id) : Nil
        @nodes.select! do |node|
          if node.refresh_if_needed(this_nodes_id)
            true
          else
            node.close
            false
          end
        end
      end

      private def calculate_middle
        (@range.end - @range.begin) / 2 + @range.begin
      end
    end
  end
end
