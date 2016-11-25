require "../../spec_helper"

Spec2.describe Torrent::Bencode::Lexer do
  it "lexes" do
    [
      { "i123e", [ Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::Integer, 123i64) ]},
      { "i-456e", [ Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::Integer, -456i64) ]},
      { "4:spam", [ Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::ByteString, 0i64, "spam".to_slice) ]},
      { "3:foo3:bar", [
        Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::ByteString, 0i64, "foo".to_slice),
        Torrent::Bencode::Token.new(5, Torrent::Bencode::TokenType::ByteString, 0i64, "bar".to_slice) ]},
      { "5:yaddai0e", [
        Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::ByteString, 0i64, "yadda".to_slice),
        Torrent::Bencode::Token.new(7, Torrent::Bencode::TokenType::Integer, 0i64) ]},
      { "de", [
        Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::Dictionary, 0i64),
        Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::EndMarker, 0i64)
      ]},
      { "le", [
        Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::List, 0i64),
        Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::EndMarker, 0i64)
      ]},
      { "li123ee", [
        Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::List, 0i64),
        Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::Integer, 123i64),
        Torrent::Bencode::Token.new(6, Torrent::Bencode::TokenType::EndMarker, 0i64)
      ]},
      { "l2:eee", [
        Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::List, 0i64),
        Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::ByteString, 0i64, "ee".to_slice),
        Torrent::Bencode::Token.new(5, Torrent::Bencode::TokenType::EndMarker, 0i64)
      ]},
      { "l0:e", [
        Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::List, 0i64),
        Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::ByteString, 0i64, "".to_slice),
        Torrent::Bencode::Token.new(3, Torrent::Bencode::TokenType::EndMarker, 0i64)
      ]},
      { "llee", [
        Torrent::Bencode::Token.new(0, Torrent::Bencode::TokenType::List, 0i64),
        Torrent::Bencode::Token.new(1, Torrent::Bencode::TokenType::List, 0i64),
        Torrent::Bencode::Token.new(2, Torrent::Bencode::TokenType::EndMarker, 0i64),
        Torrent::Bencode::Token.new(3, Torrent::Bencode::TokenType::EndMarker, 0i64)
      ]}
    ].each do |string, expected|
      lexer = Torrent::Bencode::Lexer.new(IO::Memory.new(string.to_slice))

      expected.each do |tok|
        expect(lexer.next_token).to eq tok
      end

      expect(lexer.next_token).to eq Torrent::Bencode::Token.new(
        position: string.size,
        type: Torrent::Bencode::TokenType::Eof
      )

      expect(lexer.eof?).to be_true
    end
  end

  it "fails for 4:abc" do
    lexer = Torrent::Bencode::Lexer.new(IO::Memory.new("4:abc".to_slice))
    expect{ lexer.next_token }.to raise_error(Torrent::Bencode::Lexer::Error, match /premature end of string/i)
  end

  it "fails for -4:abc" do
    lexer = Torrent::Bencode::Lexer.new(IO::Memory.new("-4:abc".to_slice))
    expect{ lexer.next_token }.to raise_error(Torrent::Bencode::Lexer::Error, match /unknown token/i)
  end

  it "fails for i123" do
    lexer = Torrent::Bencode::Lexer.new(IO::Memory.new("i123".to_slice))
    expect{ lexer.next_token }.to raise_error(Torrent::Bencode::Lexer::Error, match /premature end/i)
  end

  it "fails for i12a" do
    lexer = Torrent::Bencode::Lexer.new(IO::Memory.new("i12a".to_slice))
    expect{ lexer.next_token }.to raise_error(Torrent::Bencode::Lexer::Error, match /unexpected byte/i)
  end

  it "fails for z" do
    lexer = Torrent::Bencode::Lexer.new(IO::Memory.new("z".to_slice))
    expect{ lexer.next_token }.to raise_error(Torrent::Bencode::Lexer::Error, match /unknown token/i)
  end
end
