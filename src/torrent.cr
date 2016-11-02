require "digest/sha1"
require "uri"
require "http/client"
require "logger"

require "cute" # Shard, github.com/Papierkorb/cute

# A BitTorrent client library in pure Crystal.
module Torrent
  @@logger : Logger?

  # Base class for all custom errors in `Torrent`
  class Error < Exception; end

  #
  def self.logger
    @@logger
  end

  def self.logger=(log)
    @@logger = log
  end
end

require "./torrent/bencode"
require "./torrent/*"
require "./torrent/util/*"
require "./torrent/piece_picker/*"
require "./torrent/manager/*"
require "./torrent/file_manager/*"
require "./torrent/client/*"
require "./torrent/extension/*"
