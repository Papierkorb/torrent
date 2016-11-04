require "./tracker" # Require order ...

module Torrent
  module Client
    # Client for a Torrent Tracker to find peers for a specific torrent.
    class HttpTracker < Tracker
      # Builds a client for contacting the tracker at *url*
      def initialize(@url : URI)
        @log = Util::Logger.new("Tracker/#{@url.host}")
      end

      # Asks the tracker for peers of *transfer*.  Raises on error.
      def get_peers(transfer : Torrent::Transfer) : Array(Structure::PeerInfo)
        @last_request = Time.now
        response = do_get build_announce_url(transfer)
        list = Structure::PeerList.from_bencode(response)

        @retry_interval = list.interval.to_i32
        @log.debug "Received #{list.peers.size} IPv4 and #{list.peers6.size} IPv6 peers"
        @log.debug "Retry interval is #{@retry_interval} seconds"

        list.peers + list.peers6
      end

      # Returns statistics of the given *info_hashes*.  Raises on error.
      def scrape(info_hashes : Enumerable(Bytes)) : Structure::ScrapeResponse
        response = do_get build_scrape_url(info_hashes)
        Structure::ScrapeResponse.from_bencode(response)
      end

      private def do_get(url)
        @log.debug "GET #{url}"
        response = HTTP::Client.get(url)

        if response.status_code != 200
          raise Error.new("Request failed with HTTP code #{response.status_code}")
        end

        response.body.to_slice
      end

      private def build_announce_url(transfer)
        port = transfer.manager.port
        raise Error.new("Manager is not listening on a port") if port.nil?

        url = @url.dup
        url.query = HTTP::Params.from_hash({
          "peer_id" => transfer.peer_id,
          "info_hash" => String.new(transfer.info_hash),
          "port" => port.to_s,
          "uploaded" => transfer.uploaded.to_s,
          "downloaded" => transfer.downloaded.to_s,
          "left" => transfer.left.to_s,
          "event" => status_string(transfer.status),
          "compact" => "1",
        })

        # Note: We only support `compact` responses. Nowadays, trackers either
        #       don't support the non-compact form at all, or respond with
        #       invalid Bencoded data.  (Looking at you, "mimosa")

        url
      end

      private def build_scrape_url(info_hashes)
        url = @url.dup
        # This is the official, documented way of doing it :)
        url.path = url.path.not_nil!.sub("announce", "scrape")
        url.query = HTTP::Params.build do |form|
          info_hashes.each do |hsh|
            form.add("info_hash", String.new(hsh))
          end
        end

        url
      end

      private def status_string(status : Transfer::Status) : String
        case status
        when Transfer::Status::Stopped
          "stopped"
        when Transfer::Status::Running
          "started"
        when Transfer::Status::Completed
          "completed"
        else
          raise "Torrent::Client::Tracker#status_string is seriously broken"
        end
      end
    end
  end
end
