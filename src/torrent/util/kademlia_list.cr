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

      delegate :[], :[]?, each, size, unsafe_at, to: @array

      # Clears the list of all elemenets.  Also lets the user reset the
      # comparison value.
      def clear(comparison : BigInt = @comparison)
        @comparison = comparison
        @array.clear
        @distances.clear
      end

      # Takes out the first element of the list and returns it.
      def shift : T
        @distances.shift
        @array.shift
      end

      # Tries to add *element* to the list.  On success returns `true`, else
      # returns `false`.  If the list already contains *element*, `false` is
      # returned.
      def try_add(element : T) : Bool
        return false if @array.includes?(element)
        dist = element.kademlia_distance(@comparison)

        # Make room at the end
        if @array.size >= @max_size
          # Discard if the node list size has been reached and the distance
          # is greater than the farthest distance in the list.
          return false if dist > @distances.last

          @array.pop
          @distances.pop
        end

        idx = @distances.index(&.>=(dist))
        idx = @array.size if idx.nil?

        @array.insert idx, element
        @distances.insert idx, dist

        true
      end

      # Adds *element* to the sorted element list
      def <<(element : T) : self
        try_add element
        self
      end
    end
  end
end
