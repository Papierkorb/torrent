module Torrent
  module Util
    # List which uses `T#kademlia_distance` to sort elements when they're added,
    # while enforcing a maximum size, discarding the farthest element when
    # additional space is needed.
    class KademliaList(T)
      include Enumerable(T)
      include Indexable(T)

      def initialize(@comparison : BigInt, @max_size : Int32)
        @distances = Array(BigInt).new(@max_size)
        @array = Array(T).new(@max_size)
      end

      # Returns the element list as `Array(T)`
      def to_a
        @array
      end

      delegate :[], :[]?, each, size, to: @array

      # Clears the list of all elemenets
      def clear
        @array.clear
        @distances.clear
      end

      # Adds *element* to the sorted element list
      def <<(element : T) : self
        dist = element.kademlia_distance(@comparison)

        # Make room at the end
        if @array.size >= @max_size
          # Discard if the node list size has been reached and the distance
          # is greater than the farthest distance in the list.
          return self if dist > @distances.last

          @array.pop
          @distances.pop
        end

        idx = @distances.index{|other| other >= dist}
        idx = @array.size if idx.nil?

        @array.insert idx, element
        @distances.insert idx, dist

        self
      end
    end
  end
end
