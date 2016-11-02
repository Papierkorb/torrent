require "../../spec_helper"

private def it_lexes(string, expected : Array(Torrent::Bencode::Token))
  it "lexes #{string.inspect}" do
    lexer = Torrent::Bencode::Lexer.new(MemoryIO.new(string.to_slice))

    expected.each do |tok|
      lexer.next_token.should eq tok
    end

    lexer.next_token.should eq Torrent::Bencode::Token.new(
      position: string.size,
      type: Torrent::Bencode::TokenType::Eof
    )

    lexer.eof?.should be_true
  end
end

private def it_fails(string, message)
  it "fails for #{string.inspect} with #{message.inspect}" do
    lexer = Torrent::Bencode::Lexer.new(MemoryIO.new(string.to_slice))
    expect_raises(Torrent::Bencode::Lexer::Error, message){ lexer.next_token }
  end
end

describe Torrent::Bencode::Lexer do
  it_lexes "i123e", [ Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::Integer, 123i64) ]
  it_lexes "i-456e", [ Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::Integer, -456i64) ]
  it_lexes "4:spam", [ Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::ByteString, 0i64, "spam".to_slice) ]
  it_lexes "3:foo3:bar", [
    Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::ByteString, 0i64, "foo".to_slice),
    Torrent::Bencode::Token.new(5, Torrent::Bencode::TokenType::ByteString, 0i64, "bar".to_slice) ]
  it_lexes "5:yaddai0e", [
    Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::ByteString, 0i64, "yadda".to_slice),
    Torrent::Bencode::Token.new(7, Torrent::Bencode::TokenType::Integer, 0i64) ]
  it_lexes "de", [
    Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::Dictionary, 0i64),
    Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::EndMarker, 0i64)
  ]
  it_lexes "le", [
    Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::List, 0i64),
    Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::EndMarker, 0i64)
  ]
  it_lexes "li123ee", [
    Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::List, 0i64),
    Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::Integer, 123i64),
    Torrent::Bencode::Token.new(6, Torrent::Bencode::TokenType::EndMarker, 0i64)
  ]
  it_lexes "l2:eee", [
    Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::List, 0i64),
    Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::ByteString, 0i64, "ee".to_slice),
    Torrent::Bencode::Token.new(5, Torrent::Bencode::TokenType::EndMarker, 0i64)
  ]
  it_lexes "l0:e", [
    Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::List, 0i64),
    Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::ByteString, 0i64, "".to_slice),
    Torrent::Bencode::Token.new(3, Torrent::Bencode::TokenType::EndMarker, 0i64)
  ]
  it_lexes "llee", [
    Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::List, 0i64),
    Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::List, 0i64),
    Torrent::Bencode::Token.new(2, Torrent::Bencode::TokenType::EndMarker, 0i64),
    Torrent::Bencode::Token.new(3, Torrent::Bencode::TokenType::EndMarker, 0i64)
  ]

  it_fails "4:abc", /premature end of string/i
  it_fails "-4:abc", /unknown token/i
  it_fails "i123", /premature end/i
  it_fails "i12a", /unexpected byte/i
  it_fails "z", /unknown token/i
end
