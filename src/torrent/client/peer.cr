module Torrent
  module Client
    abstract class Peer
      enum State
        NotConnected # Not connected to any peer
        Connecting # Establishing TCP connection
        Handshake # Waiting for handshake
        InfoHash # Waiting for the info file SHA1-hash
        PeerId # Waiting for the peer id
        PacketSize # Waiting for the next packet size (UInt32)
        Packet # Waiting for the next packet data
      end

      @[Flags]
      enum Status
        ChokedByPeer
        ChokingPeer
        InterestedInPeer
        PeerIsInterested
      end

      abstract class Command
      end

      # Closes the peer connection
      class CloseCommand < Command

        # If to close the connection **without** flushing write buffers.
        getter? kill : Bool

        def initialize(@kill = false)
        end
      end

      # Forced maximum packet size. If a client tries to send something bigger
      # than this, no matter the cause, the connection will be killed.
      MAX_PACKET_SIZE = 4 * 1024 * 1024

      # Default maximum of open outgoing piece-block requests.
      MAX_OPEN_REQUESTS = 128

      # The transfer of this peer connection.
      # Is a property so that we can swap the used `transfer` when operating in
      # server mode.
      property! transfer : Torrent::Transfer

      # The transfer manager of this peer
      getter manager : Manager::Base

      # Current state of the peer connection
      getter state : State = State::NotConnected

      # Status flags of the transfer
      property status : Status = Status::ChokingPeer | Status::ChokedByPeer

      # Bitfield of pieces the remote peer has
      getter bitfield : Util::Bitfield

      # The command channel
      getter command_channel : Channel(Command)

      # The peer id of the remote peer. Populated through the handshake,
      # thus if the connection is ready, it's safe to assume it being not nil.
      getter remote_peer_id : Bytes?

      # Count of bytes received from this peer in total
      getter bytes_received : UInt64 = 0u64

      # Count of bytes sent to this peer in total
      getter bytes_sent : UInt64 = 0u64

      # Last moment a packet was received. Initialized to `Time.now`.
      getter last_received : Time

      # Send queue.
      @send_queue : Deque(Tuple(UInt32, UInt32, UInt32))

      # == Signals ==

      # Emitted when the handshake has been received. Note that at this point
      # there's no peer id, etc., available yet.
      Cute.signal handshake_received

      # Emitted when a status bit has been set
      Cute.signal status_bit_set(bit : Status)

      # Emitted when a status bit has been cleared
      Cute.signal status_bit_cleared(bit : Status)

      # Emitted when a piece has been downloaded.
      Cute.signal piece_download_completed(piece : Protocol::Piece, data : Bytes)

      # Emitted when the remote peers info hash has been received
      Cute.signal info_hash_received(info_hash : Bytes)

      # Emitted when the handshake has just been sent to the remote peer
      Cute.signal handshake_sent

      # Emitted when the connection is ready for use. *peer_id* is the remotes
      # peer peer-id.
      Cute.signal connection_ready(peer_id : Bytes)

      # Emitted when the connection was lost
      Cute.signal connection_lost

      # Emitted when the remote peer sent a ping packet
      Cute.signal ping_received

      # Emitted when the remote peer sent a bitfield
      Cute.signal bitfield_received

      # Emitted when the remote peer announced it acquired a new piece.
      Cute.signal have_received(piece_index : UInt32)

      # Emitted when the remote peer rejected a request from us
      Cute.signal request_rejected(rejection : Protocol::RejectRequest)

      # Emitted when a piece has been suggested to us
      Cute.signal piece_suggested(piece_index : UInt32)

      # Emitted when a allowed fast-list has been received
      Cute.signal fast_list_received(list : Array(UInt32))

      # Initialized by implementations of this class
      getter log : Util::Logger

      # Does the peer support the extension protocol (BEP-0010)?
      getter? extension_protocol : Bool = false

      # Does the peer support the fast extension (BEP-0006)?
      getter? fast_extension : Bool = false

      # Mapping from the extension name to the id.
      getter extension_map : Hash(String, UInt8)

      # Count of max concurrent outgoing piece-block requests.
      # Remote peers can signal a different limit through the extension
      # protocol.
      property max_concurrent_requests : Int32 = MAX_OPEN_REQUESTS

      def initialize(@manager : Manager::Base, @transfer : Torrent::Transfer?)
        @log = Util::Logger.new("Peer")

        t = @transfer
        @bitfield = Util::Bitfield.new(t ? t.piece_count : 0)

        @send_queue = Deque(Tuple(UInt32, UInt32, UInt32)).new
        @command_channel = Channel(Command).new
        @extension_map = Hash(String, UInt8).new
        @last_received = Time.now
      end

      # Sends a close command to the peer
      def close
        @command_channel.send CloseCommand.new
      end

      def max_concurrent_piece_requests
        blocks = transfer.piece_size / Util::RequestList::REQUEST_BLOCK_SIZE
        @max_concurrent_requests / blocks
      end

      private def set_state(state : State)
        return if @state == state
        @state = state
      end

      # Sends the packet to the remote peer. If *payload* is `nil`, no payload
      # is sent for this packet.
      abstract def send_packet(type : UInt8, payload : Bytes? = nil)

      # Sends *data* to the remote peer, only prepending the length of the data
      # before sending.
      abstract def send_data(data : Bytes)

      # Sends the data to the remote peer later.
      abstract def send_data(&block : -> Bytes?)

      # The remote address of this peer
      abstract def address : String

      # The remote port of this peer
      abstract def port : UInt16

      # Runs a single-step, where the peer can check for new incoming data
      # and transfer scheduled outgoing data.
      abstract def run_once

      # Chokes the peer. The peer should now cease to send us requests for
      # pieces. This also clears the list of waiting piece requests on our
      # end.
      def choke_peer
        @status |= Status::ChokingPeer
        send_packet(Wire::MessageType::Choke.value)
        status_bit_set.emit Status::ChokingPeer
        @send_queue.clear unless @fast_extension
        @log.debug "Choking peer"
      end

      # Unchokes the peer. The peer is now allowed to send us new requests.
      def unchoke_peer
        @status &= ~Status::ChokingPeer
        send_packet(Wire::MessageType::Unchoke.value)
        status_bit_cleared.emit Status::ChokingPeer
        @log.debug "Unchoking peer"
      end

      # Tells the peer that we're interested in downloading pieces from it.
      def express_interest
        @status |= Status::InterestedInPeer
        send_packet(Wire::MessageType::Interested.value)
        status_bit_set.emit Status::InterestedInPeer
        @log.debug "Expressing interest"
      end

      # Tells the peer that we have no interest in downloading pieces from it.
      def express_no_interest
        @status &= ~Status::InterestedInPeer
        send_packet(Wire::MessageType::NotInterested.value)
        status_bit_cleared.emit Status::InterestedInPeer
        @log.debug "Expressing NO interest"
      end

      # Sends a ping.
      def send_ping
        @log.debug "Sending PING"
        send_data(Bytes.new(0))
      end

      # Sends the bitfield packet, which tells the remote peer which pieces we
      # have already acquired.
      def send_bitfield(bitfield : Bytes)
        @log.debug "Sending bitfield"
        send_packet(Wire::MessageType::Bitfield.value, bitfield)
      end

      # Sends the *bitfield*. If the remote peer supports the fast extensions,
      # the method will send a `HaveAll` or `HaveNone` packet instead of an all
      # ones or all zeroes bitfield.
      def send_bitfield(bitfield : Util::Bitfield)
        if @fast_extension && bitfield.all_ones?
          send_have_all
        elsif @fast_extension && bitfield.all_zero?
          send_have_none
        else
          send_bitfield bitfield.data
        end
      end

      # Sends a HaveAll packet, indicating that we have all pieces.
      def send_have_all
        raise Error.new("Fast extension not supported by this peer") unless @fast_extension

        @log.debug "Telling peer that we have all pieces"
        send_packet(Wire::MessageType::HaveAll.value)
      end

      # Sends a HaveNone packet, indicating that we have no pieces yet.
      def send_have_none
        raise Error.new("Fast extension not supported by this peer") unless @fast_extension

        @log.debug "Telling peer that we have no pieces at all"
        send_packet(Wire::MessageType::HaveNone.value)
      end

      # Sends a SuggestPiece packet, suggesting the remote peer to download the
      # given piece.
      def suggest_piece(piece_index : UInt32)
        raise Error.new("Fast extension not supported by this peer") unless @fast_extension

        data = Protocol::SuggestPiece.new(piece_index)
        send_packet(Wire::MessageType::SuggestPiece.value, data.to_bytes)
      end

      # Explicitly rejects a piece request, e.g. because we don't have it.
      #
      # Also removes the corresponding request from the open requests list.
      def reject_request(piece_index : UInt32, start : UInt32, length : UInt32)
        raise Error.new("Fast extension not supported by this peer") unless @fast_extension

        reject = Protocol::RejectRequest.new(piece_index, start, length)
        @send_queue.delete({ piece_index, start, length })
        send_packet(Wire::MessageType::RejectRequest.value, reject.to_bytes)
      end

      def send_allowed_fast_list(pieces : Array(UInt32))
        raise Error.new("Fast extension not supported by this peer") unless @fast_extension

        data = pieces.map{|idx| Util::Endian.to_network idx}.to_a
        payload = Bytes.new(data.to_unsafe.as(UInt8*), pieces.size * sizeof(UInt32))
        send_packet(Wire::MessageType::AllowedFast.value, payload)
      end

      # Sends a request to download the piece at *piece_index*, beginning at
      # the byte *offset* and following *length* bytes. *length* is commonly
      # a power-of-two.
      def send_request(piece_index : UInt32, start : UInt32, length : UInt32)
        request = Protocol::Request.new(piece_index, start, length)
        send_packet Wire::MessageType::Request.value, request.to_bytes
      end

      # Sends a packet to a protocol extension per BEP-0010.
      def send_extended(message_id : UInt8, payload : Bytes? = nil)
        raise Error.new("Peer does not support extensions") unless @extension_protocol

        size = payload.try(&.size) || 0
        packet = Bytes.new(2 + size)
        packet[0] = Wire::MessageType::Extended.value
        packet[1] = message_id
        (packet + 2).copy_from(payload) if payload

        # @log.debug "Sending Extended using message id #{message_id} with payload of #{size} Bytes"
        send_data packet
      end

      # Sends a packet to a named extension. Yields if the remote peer does not
      # support it.
      def send_extended(message : String, payload : Bytes? = nil)
        return yield unless @extension_protocol

        if id = @extension_map[message]?
          send_extended(id, payload)
        else
          yield
        end
      end

      # Sends a packet to a named extension. Raises if the remote peer does not
      # support it.
      def send_extended(message : String, payload : Bytes? = nil)
        raise Error.new("Peer does not support extensions") unless @extension_protocol

        send_extended(message, payload) do
          raise Error.new("Peer does not support the #{message.inspect} extension")
        end
      end

      # Sends a packet to a named extension. Returns `true` if the extension is
      # supported by the remote peer, or `false` if it does not.
      def send_extended?(message : String, payload : Bytes? = nil)
        success = true
        send_extended(message, payload){ success = false }
        success
      end

      # Cancels a previous piece request.
      def send_cancel(piece_index : UInt32, start : UInt32, length : UInt32)
        cancel = Protocol::Cancel.new(piece_index, start, length)
        # @log.debug "Sending Cancel for #{piece_index} [#{start}, #{length}]"
        send_packet Wire::MessageType::Cancel.value, cancel.to_bytes
      end

      # Sends a Have packet to the remote peer, announcing that we now have a
      # valid copy of the piece in question.
      def send_have(piece_index : UInt32)
        have = Protocol::Have.new(piece_index)
        send_packet Wire::MessageType::Have.value, have.to_bytes
      end

      # Clears the request list **of** the peer.  No notification is sent to the
      # peer.
      def cancel_all_from_peer
        @send_queue.clear
      end

      def handle_packet(id : UInt8, payload : Bytes)
        @last_received = Time.now

        case Wire::MessageType.from_value(id)
        when Wire::MessageType::Choke
          @status |= Status::ChokedByPeer
          @log.debug "Have been choked by peer"
          status_bit_set.emit Status::ChokedByPeer
        when Wire::MessageType::Unchoke
          @status &= ~Status::ChokedByPeer
          @log.debug "Have been UNchoked by peer"
          status_bit_cleared.emit Status::ChokedByPeer
        when Wire::MessageType::Interested
          @status |= Status::PeerIsInterested
          @log.debug "Peer is interested"
          status_bit_set.emit Status::PeerIsInterested
        when Wire::MessageType::NotInterested
          @status &= ~Status::PeerIsInterested
          @log.debug "Peer is NOT interested"
          status_bit_cleared.emit Status::PeerIsInterested
        when Wire::MessageType::Have
          if payload.size != sizeof(Wire::Have)
            raise Error.new("Peer sent Have packet of size #{payload.size}, but expected was #{sizeof(Wire::Have)}")
          end

          handle_have(payload)
        when Wire::MessageType::Bitfield
          byte_count = Util::Bitfield.bytesize(transfer.piece_count)

          if payload.size != byte_count
            raise Error.new("Peer sent Bitfield packet of size #{payload.size}, but expected was #{byte_count}")
          end

          @bitfield = Util::Bitfield.new(payload, transfer.piece_count)
          bitfield_received.emit
        when Wire::MessageType::Request
          if payload.size != sizeof(Wire::Request)
            raise Error.new("Peer sent Request packet of size #{payload.size}, but expected was #{sizeof(Wire::Request)}")
          end

          handle_request(payload)
        when Wire::MessageType::Piece
          if payload.size < sizeof(Wire::Piece)
            raise Error.new("Peer sent Piece packet of size #{payload.size}, but is less than #{sizeof(Wire::Piece)}")
          end

          handle_piece payload
        when Wire::MessageType::Cancel
          if payload.size != sizeof(Wire::Request)
            raise Error.new("Peer sent Cancel packet of size #{payload.size}, but expected was #{sizeof(Wire::Request)}")
          end

          handle_cancel(payload)
        when Wire::MessageType::Extended
          if payload.size < sizeof(Wire::Extended)
            raise Error.new("Peer sent Extended packet of size #{payload.size}, but expected was at least #{sizeof(Wire::Extended)}")
          end

          handle_extended(payload)
        when Wire::MessageType::HaveAll
          @bitfield = Util::Bitfield.new(transfer.piece_count, 0xFFu8)
          bitfield_received.emit
        when Wire::MessageType::HaveNone
          @bitfield = Util::Bitfield.new(transfer.piece_count, 0u8)
          bitfield_received.emit
        when Wire::MessageType::SuggestPiece
          if payload.size != sizeof(Wire::Have)
            raise Error.new("Peer sent SuggestPiece packet of size #{payload.size}, but expected was #{sizeof(Wire::Have)}")
          end

          suggestion = Protocol::SuggestPiece.from(payload)
          piece_suggested.emit suggestion.piece
        when Wire::MessageType::RejectRequest
          if payload.size != sizeof(Wire::Request)
            raise Error.new("Peer sent RejectRequest packet of size #{payload.size}, but expected was #{sizeof(Wire::Request)}")
          end

          handle_rejection(payload)
        when Wire::MessageType::AllowedFast
          unless payload.size.divisible_by?(sizeof(UInt32))
            raise Error.new("Peer sent AllowedFast packet of size #{payload.size}, but that's not divisble by 4")
          end

          handle_allowed_fast(payload)
        end
      end

      private def handle_have(payload)
        have = Protocol::Have.from(payload)
        @bitfield[have.piece] = true

        have_received.emit(have.piece)
        @log.debug "Peer now owns piece #{have.piece}"
      end

      private def handle_piece(payload)
        piece = Protocol::Piece.from(payload)
        data = payload + sizeof(Protocol::Piece)

        @log.debug "Received piece #{piece.index} from peer (#{data.size} Bytes)"
        piece_download_completed.emit piece, data
      end

      private def handle_request(payload)
        request = Protocol::Request.from(payload)
        tuple = { request.index, request.start, request.length }
        @send_queue << tuple

        @log.info "Peer requests piece #{request.index} [#{request.start}, #{request.length}]"

        send_data do
          do_it = @send_queue.delete(tuple)
          @log.info "Fulfilling request #{tuple}: #{do_it}"
          fulfill_request(request) if do_it
          nil
        end
      end

      private def fulfill_request(request)
        packet = Bytes.new(1 + sizeof(Wire::Piece) + request.length)
        data = packet + sizeof(Wire::Piece) + 1
        piece = Protocol::Piece.new(index: request.index, offset: request.start)
        packet[0] = Wire::MessageType::Piece.value
        (packet + 1).copy_from(piece.to_bytes)

        @log.debug "Sending piece #{request.index} [#{request.start}, #{request.length}]"
        transfer.read_piece_for_upload(request.index, request.start, data)
        send_data packet
      rescue error
        @log.error "Failed to fulfill request #{request.index} [#{request.start}, #{request.length}]"
        @log.error error
      end

      private def handle_cancel(payload)
        cancel = Protocol::Cancel.from(payload)
        @send_queue.delete(cancel)

        @log.debug "Peer cancelled requested piece #{cancel.index} [#{cancel.start}, #{cancel.length}]"
      end

      private def handle_extended(payload)
        header = Protocol::Extended.from(payload)
        data = payload + sizeof(Wire::Extended)

        @log.debug "Peer invokes extension #{header.message_id} with payload of #{data.size} Bytes"
        @manager.extensions.invoke(self, header.message_id, data)
      end

      private def handle_rejection(payload)
        rejection = Protocol::RejectRequest.from(payload)
        @log.debug "Peer rejected request for piece #{rejection.index} [#{rejection.start}, #{rejection.length}]"
        request_rejected.emit rejection
      end

      private def handle_allowed_fast(payload)
        ptr = payload.pointer(payload.size).as(UInt32*)
        data = Slice(UInt32).new(ptr, payload.size / sizeof(UInt32))

        list = Array(UInt32).new(data.size) do |idx|
          Util::Endian.to_host data[idx]
        end

        @log.debug "Peer sent fast list with #{list.size} elements: #{list.inspect}"
        fast_list_received.emit list
      end
    end
  end
end
