private def pull_parser(input : Bytes)
  pull_parser(MemoryIO.new input)
end

private def pull_parser(input : IO)
  lexer = Torrent::Bencode::Lexer.new(input)
  Torrent::Bencode::PullParser.new(lexer)
end

{% for type, func in { UInt8: :u8, UInt16: :u16, UInt32: :u32, UInt64: :u64, Int8: :i8, Int16: :i16, Int32: :i32, Int64: :i64 } %}
  struct {{ type.id }}
    def self.new(pull : Torrent::Bencode::PullParser) : self
      pull.read_integer.to_{{ func.id }}
    end

    def self.from_bencode(bytes_or_io : Bytes | IO) : self
      new pull_parser(bytes_or_io)
    end

    def to_bencode(io : IO) : IO
      io.print "i#{self}e"
      io
    end
  end
{% end %}

class String
  def self.new(pull : Torrent::Bencode::PullParser) : self
    String.new pull.read_byte_slice
  end

  def self.from_bencode(bytes_or_io : Bytes | IO) : self
    String.new pull_parser(bytes_or_io)
  end

  def to_bencode(io : IO) : IO
    to_slice.to_bencode(io)
  end
end

struct Slice(T)
  def self.new(pull : Torrent::Bencode::PullParser) : self
    pull.read_byte_slice
  end

  def self.from_bencode(bytes_or_io : Bytes | IO) : self
    new pull_parser(bytes_or_io)
  end

  def to_bencode(io : IO) : IO
    io.print "#{bytesize}:"
    io.write self
    io
  end
end

class Hash(K, V)
  def self.new(pull : Torrent::Bencode::PullParser) : self
    hsh = Hash(K, V).new

    pull.read_dictionary do
      hsh[String.new(pull)] = V.new(pull)
    end

    hsh
  end

  def self.from_bencode(bytes_or_io : Bytes | IO) : self
    new pull_parser(bytes_or_io)
  end

  def to_bencode(io : IO) : IO
    io.print "d"

    keys.sort.each do |key|
      key.to_bencode(io)
      self[key].to_bencode(io)
    end

    io.print "e"
    io
  end
end

class Array(T)
  def self.new(pull : Torrent::Bencode::PullParser) : self
    ary = Array(T).new

    pull.read_list do
      ary << T.new(pull)
    end

    ary
  end

  def self.from_bencode(bytes_or_io : Bytes | IO) : self
    new pull_parser(bytes_or_io)
  end

  def to_bencode(io : IO) : IO
    io.print "l"
    each(&.to_bencode(io))
    io.print "e"
    io
  end
end

abstract struct Enum
  def self.new(pull : Torrent::Bencode::PullParser) : self
    from_value pull.read_integer
  end

  def to_bencode(io : IO) : IO
    value.to_bencode(io)
  end
end

struct Bool
  def self.new(pull : Torrent::Bencode::PullParser) : self
    pull.read_integer != 0
  end

  def Bool.from_bencode(bytes_or_io : Bytes | IO) : self
    Bool.new pull_parser(bytes_or_io)
  end

  def to_bencode(io : IO) : IO
    io.print self ? "i1e" : "i0e"
    io
  end
end

class Object
  def to_bencode : Bytes
    io = MemoryIO.new
    to_bencode(io)
    io.to_slice
  end
end
