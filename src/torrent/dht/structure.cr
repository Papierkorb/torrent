module Torrent
  module Dht
    # DHT datagram structures
    module Structure

      # Abstract KRPC message structure
      abstract struct Message
        # The message transaction
        getter transaction : Bytes

        def initialize(@transaction : Bytes)
        end

        def initialize(any)
          @transaction = any["t"].to_slice
        end

        # Builds the correct `Message` sub-class for this *any*.
        def self.from(any)
          case type = any["y"].to_s
          when "q"
            Query.new(any)
          when "r"
            Response.new(any)
          when "e"
            Error.new(any)
          else
            raise ArgumentError.new("Unknown type #{type.inspect}")
          end
        end
      end

      # KRPC "q" - Query message
      struct Query < Message
        # The method to call
        getter method : String

        # The method arguments
        getter args : Bencode::Any::AnyHash

        def initialize(transaction, @method, @args)
          super transaction
        end

        def initialize(any)
          super
          @method = any["q"].to_s
          @args = any["a"].to_h
        end

        # Builds a `Response` to this query
        def response(data : Bencode::Any::AnyHash)
          Response.new(@transaction, data)
        end

        # Builds an `Error` to this query
        def error(code : ErrorCode, message : String? = nil)
          Error.new(@transaction, code.value, message || ErrorCode.message(code))
        end

        # ditto
        def error(code : Int32, message : String)
          Error.new(@transaction, code, message)
        end

        def to_bencode
          {
            "t" => Bencode::Any.new(@transaction),
            "y" => Bencode::Any.new("q"),
            "q" => Bencode::Any.new(@method),
            "a" => @args,
          }.to_bencode
        end
      end

      # KRPC "r" - Response
      struct Response < Message
        # The response dictionary
        getter data : Bencode::Any::AnyHash

        def initialize(any)
          super
          @data = any["r"].to_h
        end

        def initialize(transaction, @data)
          super transaction
        end

        def to_bencode
          {
            "t" => Bencode::Any.new(@transaction),
            "y" => Bencode::Any.new("r"),
            "r" => @data,
          }.to_bencode
        end
      end

      # KRPC "e" - Error
      struct Error < Message
        # The error code
        getter code : Int32

        # The error message
        getter message : String

        def initialize(any)
          super

          err = any["e"]
          @code = err[0].to_i.to_i32
          @message = err[1].to_s
        end

        def initialize(transaction, @code, @message)
          super transaction
        end

        def to_bencode
          {
            "t" => Bencode::Any.new(@transaction),
            "y" => Bencode::Any.new("e"),
            "e" => Bencode::Any.new([ Bencode::Any.new(@code), Bencode::Any.new(@message) ]),
          }.to_bencode
        end
      end
    end
  end
end
