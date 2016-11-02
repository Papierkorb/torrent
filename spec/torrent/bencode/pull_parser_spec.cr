require "../../spec_helper"

private def pull(string)
  lexer = Torrent::Bencode::Lexer.new(MemoryIO.new(string.to_slice))
  Torrent::Bencode::PullParser.new(lexer)
end

Spec2.describe Torrent::Bencode::PullParser do
  # TODO: Split into #describe/#it blocks.
  it "#read_integer" do
    expect(pull("i5e").read_integer).to eq 5
  end

  it "#read_byte_slice" do
    expect(pull("4:abcd").read_byte_slice).to eq "abcd".to_slice
  end

  it "#read_dictionary" do
    parser = pull("d1:ai42e1:bi1337ee")

    parser.read_dictionary do
      expect(parser.read_byte_slice).to eq "a".to_slice
      expect(parser.read_integer).to eq 42i64
      expect(parser.read_byte_slice).to eq "b".to_slice
      expect(parser.read_integer).to eq 1337i64
    end
  end

  it "#read_list" do
    parser = pull("l1:ai42e1:bi1337ee")

    parser.read_list do
      expect(parser.read_byte_slice).to eq "a".to_slice
      expect(parser.read_integer).to eq 42i64
      expect(parser.read_byte_slice).to eq "b".to_slice
      expect(parser.read_integer).to eq 1337i64
    end
  end

  it "#read_dictionary error case" do
    expect{ pull("d").read_dictionary{ } }.to raise_error(Torrent::Bencode::PullParser::Error, match /eof/i)
  end

  it "#read_list error case" do
    expect{ pull("l").read_list{ } }.to raise_error(Torrent::Bencode::PullParser::Error, match /eof/i)
  end
end
