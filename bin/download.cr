require "../src/torrent"
require "io/hexdump"
require "colorize"

if ARGV.size < 1
  puts "Usage: download file.torrent"
  exit
end

file = Torrent::File.read(ARGV[0])

Dir.mkdir_p("downloads") # Create transfer manager(s)
files = Torrent::FileManager::FileSystem.new("downloads")
manager = Torrent::Manager::Transfer.new(files)
transfer = manager.add_transfer file

picker = Torrent::PiecePicker::RarestFirst.new(transfer)
transfer.piece_picker = picker

logger = Logger.new(File.open("download.log", "w")) # Logger
logger.level = Logger::DEBUG
Torrent.logger = logger
manager.start! # Begin downloading the torrent!
start_time = Time.now

transfer.download_completed.on do # Be notified when we're done
  elapsed = Time.now - start_time
  puts "-> Finished download after #{elapsed}"
  # exit 0
end

manager.extensions.unknown_message.on do |peer, id, payload|
  logger.error "Peer #{peer.address} #{peer.port} invoked unknown extension #{id}: #{payload.hexstring}"
end

spawn do # Update the "TUI" screen each second
  peers = Hash(Torrent::Client::Peer, UInt64).new
  STDOUT.print "\e[2J"

  loop do
    render_screen(manager, peers, STDOUT, Time.now - start_time)
    sleep 1
  end
end

sleep # Run fibers.

def readable_size(bytes)
  if bytes < 1024
    "#{bytes} B"
  elsif bytes < 1024 ** 2
    "#{bytes / 1024} KiB"
  elsif bytes < 1024 **  3
    "%.2f MiB" % { bytes / (1024.0 ** 2) }
  else
    "%.2f GiB" % { bytes / (1024.0 ** 3) }
  end
end

def timespan_s(timespan)
  "#{timespan.hours.to_s.rjust(2, '0')}:#{timespan.minutes.to_s.rjust(2, '0')}:#{timespan.seconds.to_s.rjust(2, '0')}"
end

def estimate(total_size, current_size, runtime)
  return "???" if current_size == 0 || total_size == 0

  msec = runtime.total_milliseconds
  speed = current_size.to_f64 / msec.to_f64
  remaining = (total_size - current_size).to_f64 / speed
  timespan_s Time::Span.new(0, 0, 0, 0, remaining.to_i)
end

def render_screen(manager, peers, io, runtime)
  io.print "\e[;H\e[0J" # Clear screen

  transfer = manager.transfers.first
  file = transfer.file
  done = transfer.pieces_done
  total = transfer.piece_count
  total_sec = 0
  percent = (done.to_f64 / total.to_f64 * 100.0).to_i.to_s
  io.print "Torrent #{file.info_hash[0, 10].hexstring} - PEERS " \
           "#{manager.peers.size} / #{peers.size} " \
           "+#{manager.peer_list.candidates.size} - #{percent.rjust 3}% " \
           "[#{done} / #{total} ETA #{estimate total, done, runtime}]  " \
           "#{timespan_s runtime}\n"

  io.print "ADDRESS:PORT           UP           DOWN         DOWN/s         FLAGS        PIECES\n"
  manager.peers.each do |peer|
    name = begin
      "#{peer.address}:#{peer.port}"
    rescue
      "<UNKNOWN>"
    end

    up = readable_size peer.bytes_sent
    down = readable_size peer.bytes_received
    down_sec = peer.bytes_received - (peers[peer]? || 0)
    total_sec += down_sec

    peers[peer] = peer.bytes_received
    pieces = transfer.requests.pieces_of_peer(peer).map(&.index).join(", ")
    flags = [
      (peer.status.choked_by_peer? ? 'C' : 'c'),
      (peer.status.interested_in_peer? ? 'I' : 'i'),
      '/',
      (peer.status.choking_peer? ? 'C' : 'c'),
      (peer.status.peer_is_interested? ? 'I' : 'i'),
    ].join

    leech = peer.transfer.leech_strategy.as(Torrent::LeechStrategy::Default)
    name = name.colorize.bold.to_s if leech.fast_peer?(peer)

    io.print "#{name.ljust 22} #{up.ljust 12} #{down.ljust 12} #{(readable_size(down_sec) + "/s").ljust(14)} #{flags.ljust 12} #{pieces}\n"
  end

  up = readable_size manager.peers.map(&.bytes_sent).sum
  down = readable_size manager.peers.map(&.bytes_received).sum

  io.print "\n"
  io.print "TOTAL                  #{up.ljust 12} #{down.ljust 12} #{readable_size(total_sec)}/s\n"
end
