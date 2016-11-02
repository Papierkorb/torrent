module Torrent
  module Extension

    # Base class for extension handlers
    abstract class Handler

      # The public name of the handler
      getter name : String

      # The transfer manager
      getter manager : Torrent::Manager::Base

      def initialize(@name, @manager)
      end

      # Invokes the handler from *peer* with the *payload*.
      abstract def invoke(peer : Client::Peer, payload : Bytes)

      # Called when a peer is ready, has extension support and supports
      # this handler.
      def initialize_hook(peer : Client::Peer)
        # ...
      end

      # Called periodically by the transfer manager. Occurs roughly every two
      # minutes.
      def management_tick
        # ...
      end
    end
  end
end
