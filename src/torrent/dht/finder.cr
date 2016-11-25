module Torrent
  module Dht
    # Class to find entities (nodes, peers, ...) in the DHT.
    abstract class Finder(T)
      # Count of parallel in-flight requests.  3 is the Kademlia default.
      ALPHA = 3

      # The find result.
      property result : T? = nil

      def initialize(@manager : Dht::Manager)
        @log = Util::Logger.new("Dht/Finder(#{T})")
        @candidates = Util::KademliaList(NodeAddress).new(0.to_big_i, Bucket::MAX_NODES * ALPHA)
        @seen = Array(NodeAddress).new
      end

      # Runs the finder, looking for *hash*.
      def run(hash : Bytes) : T?
        run(Util::Gmp.import_sha1 hash)
      end

       # ditto
      def run(hash : BigInt) : T?
        @candidates.clear(hash)
        @seen.clear

        @manager.nodes.closest_nodes(hash).each do |node|
          address = node.to_address
          @candidates << address
          @seen << address
        end

        # recurse_find(hash, nodes, min_distance(nodes, hash))
        iterative_find(hash)
      end

      # Called in its own `Fiber`, this method shall query *node* to look for
      # *hash*.  The method returns an array of `NodeAddress`es to ask next.
      #
      # The easiest way of ending the search is to set `#result` to something
      # non-nil.  The default `#finished?` implementation will then return the
      # value back to the user of the class.  A `nil` result is treated like
      # an empty array result.
      abstract def query_node(node : Node, hash : BigInt) : Array(NodeAddress)?

      # Called by `#recurse_find` to check if the search has finished.  It
      # returns first if the find has finished (= `true`) or not (= `false`),
      # and then the (nilable) result itself.
      #
      # The default implementation uses the `#result` property, and declares the
      # find process finished if it's no longer `nil`.
      def finished? : Tuple(Bool, T?)
        { @result != nil, @result }
      end

      # FIXME
      # This method is ugly, but I don't think right now that having multiple
      # methods would actually improve the readability on this one.
      private def iterative_find(hash : BigInt) : T?
        result_channel = Channel(T?).new
        heartbeat = Channel(NodeAddress?).new
        stop = Channel(Nil).new
        running = true

        concurrency = Math.min(ALPHA, @candidates.size)
        concurrency.times do |idx|
          Util.spawn("Finder fiber##{idx}") do
            while running && !@candidates.empty?
              done, result, closest = iterate_find_step(@candidates.shift, hash)
              @log.debug "Now have #{@candidates.size} candidates, total seen #{@seen.size}"
              break unless running

              heartbeat.send closest

              if done
                @log.debug "Found result"
                stop.send nil
                result_channel.send result
              end
            end

            concurrency -= 1
            heartbeat.send nil if running
            @log.debug "Exiting finder fiber #{idx}: #{running} #{@candidates.empty?}"
          end
        end

        Util.spawn("Finder control fiber") do
          new_best = Array(NodeAddress?).new
          current_best = nil

          while running
            select
            when node = heartbeat.receive
              new_best << node

              if new_best.size == concurrency
                challenger = closest_node(new_best.compact, hash)
                new_best.clear

                if challenger == current_best
                  @log.debug "Found no closer node - Breaking search"
                  result_channel.send nil
                  break
                end

                current_best = challenger
              end
            when stop.receive
              @log.debug "Stopping control fiber"
              break
            end
          end

          @log.debug "Exiting control fiber"
        end

        start = Time.now
        result = result_channel.receive
        @log.info "Finished search after #{Time.now - start}"
        running = false
        result
      end

      private def iterate_find_step(node_addr, hash) : Tuple(Bool, T?, NodeAddress?)
        @log.debug "Querying node at #{node_addr.address} #{node_addr.port}"
        node = @manager.find_or_connect_node(node_addr, ping: false).not_nil!
        nodes = query_node(node, hash) # Ask the node
        @manager.nodes.try_add(node)
        learn_nodes nodes if nodes

        done, result = finished? # Are we there yet?
        return { done, result, nil } if done

        # Remember candidates, repeat.
        if nodes.try(&.empty?) == false
          closest = closest_node(nodes, hash)

          nodes
            .reject{|node| @seen.includes? node}
            .each do |node|
              @candidates << node
              @seen << node
            end
        end

        { false, nil, closest }
      rescue error
        @log.error "Failed to step"
        @log.error error
        { false, nil, closest }
      end

      private def closest_node(nodes, hash)
        nodes.min_by?(&.kademlia_distance(hash))
      end

      private def learn_nodes(nodes : Enumerable(NodeAddress)) : Nil
        Util.spawn("Node learner") do
          nodes.each{|addr| learn_node addr}
        end
      end

      private def learn_node(addr)
        return unless @manager.nodes.would_accept? addr.id
        node = @manager.find_or_connect_node(addr, ping: true)
        node.close if node && !@manager.nodes.includes?(node)
      rescue error
        @log.error "Failed to learn node at #{addr.address} #{addr.port}"
        @log.error error
      end
    end
  end
end
