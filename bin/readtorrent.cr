require "../src/torrent"
require "io/hexdump"
require "colorize"

if ARGV.size < 1
  puts "Usage: readtorrent file.torrent"
  exit
end

dump_file Torrent::File.read(ARGV[0])

def readable_size(bytes)
  if bytes < 1024
    "#{bytes} B"
  elsif bytes < 1024 * 1024
    "#{bytes / 1024} KiB"
  elsif bytes < 1024 * 1024 * 1024
    "%.2f MiB" % { bytes / (1024.0 ** 2) }
  else
    "%.2f GiB" % { bytes / (1024.0 ** 3) }
  end
end

def dump_file(file)
  puts "Name: ".colorize.bold.to_s + file.name
  puts "Size: ".colorize.bold.to_s + readable_size(file.total_size) + " (#{file.total_size} Bytes)"
  puts "Pieces: ".colorize.bold.to_s + "#{file.piece_count} each with " + readable_size(file.piece_size)
  puts "Info hash: ".colorize.bold.to_s + file.info_hash.hexstring
  puts "Creator: ".colorize.bold.to_s + (file.created_by || "Unknown")
  puts "Created at: ".colorize.bold.to_s + (file.created_at || "Unknown").to_s
  puts "Trackers".colorize.bold.to_s
  file.announce_list.each do |url|
    puts "  #{url}"
  end

  puts "Files".colorize.bold.to_s

  offset = 0
  file.files.each do |descr|
    first = offset / file.piece_size
    offset += descr.length
    last = offset / file.piece_size
    last -= 1 if offset.divisible_by? file.piece_size
    puts "  #{readable_size descr.length}  #{descr.path}  [#{first}..#{last}]"
  end
end
