module Torrent
  # A parser for BEncode data
  module Bencode

    # Generic error class
    class Error < Torrent::Error; end

    # Parses the Bencode data in *bytes* and returns the structure.
    def self.load(bytes : Bytes) : Any
      load(MemoryIO.new bytes)
    end

    # Parses the Bencode data in *io* and returns the structure.
    def self.load(io : IO) : Any
      lexer = Lexer.new(io)
      pull = PullParser.new(lexer)
      Any.new(pull)
    end
  end
end

require "./bencode/*"
