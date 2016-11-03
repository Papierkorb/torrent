module Torrent
  module Extension
    # Manages extensions to the BitTorrent protocol through the protocols
    # extension mechanism (BEP-0010).
    class Manager
      # Default name of the client sent to peers
      CLIENT_NAME = "torrent.cr #{Torrent::VERSION}"

      # Hardcoded id of the handshake packet
      HANDSHAKE_ID = 0u8

      # Emitted when a *handshake* has been received from *peer*.
      # Note that a peer can send multiple handshakes during a connection.
      Cute.signal handshake_received(peer : Client::Peer, handshake : Structure::ExtendedHandshake)

      # Emitted when *peer* sent an unknown message *id* with the *payload*
      Cute.signal unknown_message(peer : Client::Peer, id : UInt8, payload : Bytes)

      # Mapping of registered handlers from their message id
      getter handlers : Hash(UInt8, Handler)

      # Name of the client announced to peers
      property client_name : String = CLIENT_NAME

      def initialize
        @handlers = Hash(UInt8, Handler).new
        @log = Util::Logger.new("Ext/Manager")
        @log.context = self
      end

      # Invokes extension handler *id* for *peer* with the *payload*
      def invoke(peer : Client::Peer, id : UInt8, payload : Bytes)
        return handle_handshake(peer, payload) if id == HANDSHAKE_ID

        if handler = @handlers[id]?
          handler.invoke(peer, payload)
        else
          unknown_message.emit(peer, id, payload)
        end
      rescue error
        @log.error "Error while processing extension message #{id} from #{peer} with payload of #{payload.size} Bytes"
        @log.error error
      end

      # Sends the extension handshake message to *peer*
      def send_handshake(peer)
        handshake = Structure::ExtendedHandshake.new
        handshake.yourip = compact_address(peer.address)
        handshake.client = client_name

        @handlers.each do |id, handler|
          handshake.mapping[handler.name] = id
        end

        peer.send_extended(HANDSHAKE_ID, handshake.to_bencode)
      end

      # Finds a handler by name.
      def []?(name : String)
        @handlers.each_value do |handler|
          return handler if handler.name == name
        end

        nil
      end

      # ditto
      def [](name : String)
        handler = self[name]?
        raise Error.new("No known handler for #{name.inspect}") if handler.nil?
        handler
      end

      def [](id : UInt8); @handlers[id]; end
      def []?(id : UInt8); @handlers[id]?; end

      # Adds *handler* and returns the assigned message id.
      # Raises if no message id is available.
      def add(handler : Handler) : UInt8
        id = find_free_message_id
        @handlers[id] = handler
        id
      end

      # Calls the management tick of all handlers, letting them do some
      # work which is to be done periodically.
      #
      # **Note:** This tick is to be called by the `Manager::Base`. It occures
      # every two minutes
      def management_tick
        @handlers.each_value do |handler|
          begin
            handler.management_tick
          rescue error
            @log.error "Error in #{handler.class}#management_tick"
            @log.error error
          end
        end
      end

      # Adds the default extensions. Called by the owning transfer manager.
      def add_default_extensions(manager)
        add PeerExchange.new(manager)
      end

      private def find_free_message_id : UInt8
        (1u8..255u8).each do |i|
          return i unless @handlers.has_key?(i)
        end

        raise Error.new("No message id available")
      end

      # Handles the extension handshake message
      private def handle_handshake(peer, payload)
        handshake = Structure::ExtendedHandshake.from_bencode(payload)
        @log.info "Peer #{peer.address} #{peer.port} sent handshake"
        @log.info " - Peers client is #{handshake.client.inspect}"
        @log.info " - Peer sees us as #{handshake.yourip.inspect}"
        @log.info " - Peer accepts #{handshake.reqq.inspect} simultaneous requests"

        if count = handshake.reqq
          peer.max_concurrent_requests = count
        end

        merge_peer_extensions(peer, handshake.mapping)
        handshake_received.emit(peer, handshake)
      end

      private def merge_peer_extensions(peer, mapping)
        target = peer.extension_map
        mapping.each do |extension, id|
          if id == HANDSHAKE_ID # Removes an extension from a peer
            target.delete extension
            @log.debug "Peer knows no extension #{extension.inspect}"
          else
            @log.debug "Peer knows extension #{extension.inspect} as ID #{id}"
            target[extension] = id
            inititalize_extension(peer, extension)
          end
        end
      end

      private def inititalize_extension(peer, extension)
        if handler = self[extension]?
          handler.initialize_hook(peer)
        end
      end

      private def compact_address(address) : Bytes
        if address.includes?('.')
          ary = address.split('.').map(&.to_u8).to_a
          Bytes.new ary.to_unsafe.as(UInt8*), ary.size
        else
          ary = address.split(':').map(&.to_u16).to_a
          Bytes.new ary.to_unsafe.as(UInt8*), ary.size * 2
        end
      end
    end
  end
end
