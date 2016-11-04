module Torrent
  module Client
    # Client for a Torrent Tracker to find peers for a specific torrent.
    abstract class Tracker

      # If no otherwise given, the seconds to wait between peer fetches.
      DEFAULT_RETRY_INTERVAL = 300

      # The tracker url
      getter url : URI

      # The last time a request was made from us. Or `nil`, if never.
      getter last_request : Time?

      # Desired time between peer fetches
      getter retry_interval : Int32 = DEFAULT_RETRY_INTERVAL

      # Builds a client for contacting the tracker at *url*
      def initialize(@url : URI)
        @log = Util::Logger.new("Tracker/#{@url.host}")
      end

      # Returns `true` if the last request is longer ago than the retry interval
      def retry_due?
        last = @last_request
        return true if last.nil? # Return true if never requested

        retry_span = Time::Span.new(0, 0, @retry_interval)
        (last + retry_span) < Time.now
      end

      # Asks the tracker for peers of *transfer*.  Raises on error.
      abstract def get_peers(transfer : Torrent::Transfer) : Array(Structure::PeerInfo)

      # Returns statistics of the given *info_hashes*.  Raises on error.
      abstract def scrape(info_hashes : Enumerable(Bytes)) : Structure::ScrapeResponse

      # Factory method to create a `Tracker` instance for the *url*.
      def self.from_url(url : URI) : Tracker
        case url.scheme
        when "http", "https"
          return HttpTracker.new(url)
        when "udp"
          return UdpTracker.new(url)
        else
          raise ArgumentError.new("Unknown tracker protocol #{url.scheme.inspect}")
        end
      end
    end
  end
end
