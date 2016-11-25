module Torrent
  module Manager

    # Base error class for managers
    class Error < Torrent::Error
    end

    # Base class for connection managers
    abstract class Base
      # This is the specified port range, but many providers block those, some
      # trackers even ban peers using one of these ports.  Instead, we're using
      # a different port range which seems to be used by other torrent clients
      # too.
      # PORT_RANGE = 6881..6889

      PORT_RANGE = 49160..65534

      # Send a PING every 2 minutes
      MANAGING_TICK = 2.minutes

      # Remove peers which have not sent a packet after some time
      PEER_TIMEOUT = 1.minutes

      # The peer list.  If you want to replace the peer list, do so right after
      # creating the manager.
      property peer_list : PeerList

      # Extension manager
      property extensions : Extension::Manager

      # Shall the DHT be used?
      property? use_dht : Bool = false

      # The DHT manager
      property dht : Dht::Manager

      def initialize
        @log = Util::Logger.new("Torrent::Manager")
        @peer_list = PeerList.new
        @extensions = Extension::Manager.new
        @dht = Dht::Manager.new
      end

      # Returns `true` if the manager accepts the *info_hash*, meaning, it knows
      # .torrent file for this hash and can serve files from it.
      abstract def accept_info_hash?(info_hash : Bytes) : Bool

      # Returns the transfer for the *info_hash*. Raises an error if no transfer
      # is known for the given hash.
      abstract def transfer_for_info_hash(info_hash : Bytes) : Torrent::Transfer

      # Returns the listening port of this manager.
      # Returns `nil` if not listening.
      # Note that valid ports are in the range `6881..6889`.
      abstract def port : Int32?

      # List of connected peers.  See also `Torrent::RequestList`.
      def peers
        @peer_list.active_peers
      end

      # Starts a managing fiber to periodically
      protected def start!
        @dht.start if @use_dht

        Util.spawn do
          loop do
            with_rescue("#ping_all_peers"){ ping_all_peers }
            with_rescue("#check_peer_timeouts"){ check_peer_timeouts }
            with_rescue("extensions.management_tick"){ extensions.management_tick }
            sleep MANAGING_TICK
          end
        end
      end

      # Sends a PING to all connected peers
      def ping_all_peers
        peers.each do |peer|
          with_rescue("peer.send_ping"){ peer.send_ping }
        end
      end

      # Checks all peers if the last received packet is too long ago.
      def check_peer_timeouts
        now = Time.now
        peers.each do |peer|
          if peer.last_received + PEER_TIMEOUT < now
            @log.info "Closing connection to peer #{peer}: Connection Timeout"
            peer.close
          end
        end
      end

      private def with_rescue(action)
        yield
      rescue error
        @log.error "Management tick failed in #{action} with error"
        @log.error error
      end
    end
  end
end
