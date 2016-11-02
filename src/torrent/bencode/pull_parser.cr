module Torrent
  module Bencode
    class PullParser
      class Error < Bencode::Error; end

      @next_token : Token?

      def initialize(@lexer : Lexer)
      end

      def read_byte_slice : Bytes
        read_token(TokenType::ByteString).byte_value.not_nil!
      end

      def read_list
        read_token(TokenType::List)

        while tok = next_token_no_eof
          break if tok.type.end_marker?

          @next_token = tok
          yield
        end
      end

      def read_dictionary
        read_token(TokenType::Dictionary)

        while tok = next_token_no_eof
          break if tok.type.end_marker?

          @next_token = tok
          yield
        end
      end

      def read_integer : Int64
        read_token(TokenType::Integer).int_value
      end

      # Reads the following token, discarding it.
      # If it's a list or dictionary, the call is recursive.
      def read_and_discard
        tok = next_token
        if tok.type.dictionary? || tok.type.list?
          read_and_discard_till_end
        end
      end

      private def read_and_discard_till_end
        depth = 1

        while tok = next_token
          if tok.type.end_marker?
            depth -= 1
            break if depth == 0
          end

          depth += 1 if tok.type.dictionary? || tok.type.list?
        end
      end

      def next_token?(type)
        peek_token.type == type
      end

      def peek_token
        next_token.tap do |tok|
          @next_token = tok
        end
      end

      private def read_token(type)
        tok = next_token
        raise "Expected a #{type} token, but got a #{tok.type} instead near #{tok.position}" if tok.type != type
        tok
      end

      def next_token : Token
        buffered = @next_token
        if buffered
          @next_token = nil
          buffered
        else
          @lexer.next_token || raise "Premature end of token stream"
        end
      end

      private def next_token_no_eof : Token
        next_token.tap do |tok|
          raise "Unexpected EOF token" if tok.type.eof?
        end
      end

      private def raise(message)
        ::raise Error.new(message)
      end
    end
  end
end
