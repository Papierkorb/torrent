module Torrent
  module Bencode
    enum TokenType : UInt8
      Eof
      Integer = 0x69u8 # i
      ByteString = 0x73u8 # s
      List = 0x6Cu8 # l
      Dictionary = 0x64u8 # d
      EndMarker = 0x65u8 # e
    end

    record Token,
      position : Int32,
      type : TokenType,
      int_value : Int64 = 0i64,
      byte_value : Bytes? = nil

    # Lexer for Bencode data. This is an internal class.
    # See `Object.from_bencode` or `Bencode.load` instead.
    class Lexer
      getter? eof : Bool = false
      getter position : Int32 = 0

      @peek_buf : UInt8?

      DIGIT_LOW = 0x30u8 # '0'
      DIGIT_HIGH = 0x39u8 # '9'
      MINUS_SIGN = 0x2Du8 # '-'
      LENGTH_SIGN = 0x3Au8 # ':'

      class Error < Bencode::Error
        getter position : Int32

        def initialize(message, @position)
          super("#{message} at byte #{@position}")
        end
      end

      def initialize(@io : IO)
      end

      def each_token
        until @eof
          yield next_token
        end
      end

      def next_token : Token
        pos = @position
        byte = next_byte?

        case byte
        when nil
          @eof = true
          Token.new(pos, TokenType::Eof)
        when TokenType::Integer.value
          integer = consume_integer(TokenType::EndMarker.value)
          Token.new(pos, TokenType::Integer, int_value: integer)
        when DIGIT_LOW..DIGIT_HIGH
          unget_byte(byte)
          data = consume_byte_string
          Token.new(pos, TokenType::ByteString, byte_value: data)
        when TokenType::List.value
          Token.new(pos, TokenType::List)
        when TokenType::Dictionary.value
          Token.new(pos, TokenType::Dictionary)
        when TokenType::EndMarker.value
          Token.new(pos, TokenType::EndMarker)
        else
          raise "Unknown token #{byte.unsafe_chr.inspect}"
        end
      end

      private def unget_byte(byte)
        @peek_buf = byte
        @position -= 1
      end

      private def next_byte? : UInt8 | Nil
        if @peek_buf
          byte = @peek_buf
          @peek_buf = nil
        else
          byte = @io.read_byte
        end

        @position += 1
        byte

      rescue IO::EOFError
        nil
      end

      private def peek_byte? : UInt8 | Nil
        @peek_buf = @io.read_byte
      rescue IO::EOFError
        nil
      end

      private def next_byte : UInt8
        byte = next_byte?
        raise "Premature end of data" if byte.nil?
        byte
      end

      private def peek_byte : UInt8
        byte = peek_byte?
        raise "Premature end of data" if byte.nil?
        byte
      end

      private def consume_integer(end_sign : UInt8) : Int64
        negate = (peek_byte == MINUS_SIGN)
        next_byte if negate

        value = read_integer(end_sign)
        negate ? -value : value
      end

      private def read_integer(end_sign : UInt8) : Int64
        value = 0i64

        while byte = next_byte
          break unless digit = read_integer_byte(byte, end_sign)
          value = value * 10 + digit
        end

        value
      end

      private def read_integer_byte(byte : UInt8, end_sign) : Int64 | Nil
        return nil if byte == end_sign

        if byte < DIGIT_LOW || byte > DIGIT_HIGH
          raise "Unexpected byte #{byte.unsafe_chr.inspect} while reading integer"
        end

        (byte - DIGIT_LOW).to_i64
      end

      private def consume_byte_string : Slice(UInt8)
        length = read_integer(LENGTH_SIGN)

        data = Slice(UInt8).new(length)
        @io.read_fully(data)

        @position += length
        data

      rescue IO::EOFError
        raise "Premature end of string"
      end

      private def raise(message)
        ::raise Error.new(message, @position)
      end
    end
  end
end
