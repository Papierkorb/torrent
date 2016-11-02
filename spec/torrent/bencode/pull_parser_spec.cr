require "../../spec_helper"

private def it_pulls(string, &block : Torrent::Bencode::PullParser -> _)
  it string.inspect do
    lexer = Torrent::Bencode::Lexer.new(MemoryIO.new(string.to_slice))
    parser = Torrent::Bencode::PullParser.new(lexer)

    block.call parser
  end
end

describe Torrent::Bencode::PullParser do
  it_pulls("i5e", &.read_integer.should(eq 5))
  it_pulls("4:abcd", &.read_byte_slice.should(eq "abcd".to_slice))

  it_pulls("d1:ai42e1:bi1337ee") do |pull|
    pull.read_dictionary do
      pull.read_byte_slice.should eq "a".to_slice
      pull.read_integer.should eq 42i64
      pull.read_byte_slice.should eq "b".to_slice
      pull.read_integer.should eq 1337i64
    end
  end

  it_pulls("l1:ai42e1:bi1337ee") do |pull|
    pull.read_list do
      pull.read_byte_slice.should eq "a".to_slice
      pull.read_integer.should eq 42i64
      pull.read_byte_slice.should eq "b".to_slice
      pull.read_integer.should eq 1337i64
    end
  end

  it_pulls("d") do |pull|
    expect_raises(Torrent::Bencode::PullParser::Error, /eof/i) do
      pull.read_dictionary{ }
    end
  end

  it_pulls("l") do |pull|
    expect_raises(Torrent::Bencode::PullParser::Error, /eof/i) do
      pull.read_list{ }
    end
  end
end
