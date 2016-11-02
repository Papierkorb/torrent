module Torrent
  module Bencode
    # Container for Bencode values, similar to `JSON::Any`.
    class Any
      class Error < Bencode::Error; end

      alias AnyArray = Array(self)
      alias AnyHash = Hash(String, self)

      # Variable type
      getter type : TokenType

      @integer : Int64 = 0i64
      @byte_string : Bytes?
      @hash : AnyHash?
      @array : AnyArray?

      # Builds an integer instance
      def initialize(integer : Int)
        @integer = integer.to_i64
        @type = TokenType::Integer
      end

      # Builds a byte-string instance
      def initialize(bytes : Bytes)
        @byte_string = bytes
        @type = TokenType::ByteString
      end

      # ditto
      def initialize(string : String)
        @byte_string = string.to_slice
        @type = TokenType::ByteString
      end

      # Builds an array instance
      def initialize(array : AnyArray)
        @array = array
        @type = TokenType::List
      end

      # Builds a hash instance
      def initialize(hash : AnyHash)
        @hash = hash
        @type = TokenType::Dictionary
      end

      # Builds an instance out of a pull-parser state
      def initialize(pull : PullParser)
        token = pull.peek_token
        @type = token.type
        @integer = 0i64

        case @type
        when TokenType::Integer
          @integer = pull.read_integer
        when TokenType::ByteString
          @byte_string = pull.read_byte_slice
        when TokenType::List
          @array = Array(self).new(pull)
        when TokenType::Dictionary
          @hash = Hash(String, self).new(pull)
        else
          raise Lexer::Error.new("Unexpected token of type #{@type}", token.position)
        end
      end

      delegate integer?, byte_string?, dictionary?, list?, to: @type

      # Is this a hash?
      def hash?
        @type.dictionary?
      end

      # Is this an array?
      def array?
        @type.list?
      end

      # Is this a string?
      def string?
        @type.byte_string?
      end

      # Returns the inner object
      def object : Int64 | Bytes | AnyArray | AnyHash
        case @type
        when TokenType::Integer then @integer
        when TokenType::ByteString then @byte_string.not_nil!
        when TokenType::List then @array.not_nil!
        when TokenType::Dictionary then @hash.not_nil!
        else
          raise Error.new("Broken any instance, type is unknown: #{@type.inspect}")
        end
      end

      # Returns the integer value, or raises if it's not an integer
      def to_i : Int64
        raise Error.new("Not an integer, but a #{@type}") unless @type.integer?
        @integer
      end

      # Returns the byte string, or raises if it's not a byte string
      def to_slice
        raise Error.new("Not a byte slice, but a #{@type}") unless @type.byte_string?
        @byte_string.not_nil!
      end

      # Returns the array, or raises if it's not an array
      def to_a
        raise Error.new("Not an array, but a #{@type}") unless @type.list?
        @array.not_nil!
      end

      # Returns the hash, or raises if it's not a hash
      def to_h
        raise Error.new("Not a hash, but a #{@type}") unless @type.dictionary?
        @hash.not_nil!
      end

      # Returns a boolean if it's an integer
      def to_b : Bool
        to_i != 0
      end

      # Serializes the inner object to Bencode.
      def to_bencode(io)
        object.to_bencode(io)
      end

      # Returns the inner objects hash
      def hash
        object.hash
      end

      def inspect(io)
        io << "<Bencode::Any "
        object.inspect(io)
        io << ">"
        io
      end

      # Calls `#to_s` on the inner object.
      # If this is a `string?`, will return the string instead.
      def to_s
        if @type.byte_string?
          String.new @byte_string.not_nil!, "UTF-8"
        else
          object.to_s
        end
      end

      # Calls `#to_s` on the inner object.
      def to_s(io)
        object.to_s(io)
      end

      # Returns the size of the array, hash or byte string.
      # Raises if this is an integer.
      def size : Int
        case @type
        when TokenType::List
          @array.not_nil!.size
        when TokenType::Dictionary
          @hash.not_nil!.size
        when TokenType::ByteString
          @byte_string.not_nil!.bytesize
        else
          raise Error.new("Expected hash or array, but is a #{@type}")
        end
      end

      # Returns `true` if the *other* any is of the same type and contains an
      # object equal to this one.
      def ==(other : self)
        @type == other.type && object == other.object
      end

      {% for suffix in [ "", "?" ] %}
        # Accesses the value for *key*.
        # Raises if this is not a hash.
        def []{{ suffix.id }}(key : String)
          to_h[key]{{ suffix.id }}
        end

        # Accesses the value at *index*.
        # Raises if this is not an array.
        def []{{ suffix.id }}(index : Int)
          to_a[index]{{ suffix.id }}
        end
      {% end %}
    end
  end
end
