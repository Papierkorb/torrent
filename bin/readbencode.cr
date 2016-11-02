require "../src/torrent"
require "io/hexdump"
require "colorize"

if ARGV.size < 1
  puts "Usage: readbencode [bencode file]"
  puts "  If no file is given, reads the file from stdin"
  exit
end

buf = Bytes.new File.size(ARGV[0])
File.open(ARGV[0]){|h| h.read_fully buf}

dump Torrent::Bencode.load(buf)
def dump(any, prefix = "")
  if any.integer?
    puts "#{prefix}(i) #{any.to_s}"
  elsif any.string?
    begin
      puts "#{prefix}(s) #{any.to_s}"
    rescue ArgumentError
      puts "#{prefix}Binary data  START (#{any.size} Bytes)"
      puts any.to_slice.hexdump
      puts "#{prefix}Binary data    END"
    end

  elsif any.list?
    puts "#{prefix}["
    pre = " " * (prefix.size) + "- "
    any.to_a.each_with_index do |any, idx|
      dump any, pre
    end
    puts "#{" " * prefix.size}]"
  elsif any.dictionary?
    puts "#{prefix}{"
    pre = " " * (prefix.size + 2)
    any.to_h.each do |key, any|
      puts "#{pre[0...-2]}#{key} ="
      dump any, pre
    end
    puts "#{" " * prefix.size}}"
  end
end
