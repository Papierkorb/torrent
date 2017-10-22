module Torrent
  module Client
    class TcpPeer < Peer

      # The peer IO
      getter socket : IPSocket

      # Has the handshake been sent?
      getter? handshake_sent : Bool

      @io : Util::AsyncIoChannel

      # Creates a peer through *socket*.
      def initialize(manager : Manager::Base, transfer : Torrent::Transfer?, @socket : IPSocket)
        super manager, transfer
        @handshake_sent = false
        @state = State::NotConnected
        @io = Util::AsyncIoChannel.new(@socket)
        @log.context = "TCP/#{@socket.remote_address}"

        # Expect the handshake packet first.
        set_state State::Handshake

        Cute.connect @io.error_occured, on_io_error_occured(error : Exception)
        @io.start
      end

      private def on_io_error_occured(error : Exception)
        @log.error "IO read/write error occured - Connection lost!"
        @log.error error
        connection_lost.emit
      end

      def address : String
        @socket.remote_address.address
      end

      def port : UInt16
        @socket.remote_address.port.to_u16
      end

      def run_once
        select
        when incoming = @io.read_channel.receive
          handle_data(incoming)
        when command = @command_channel.receive
          handle_command(command)
        end
      end

      def handle_command(command)
        case command
        when CloseCommand
          @log.info "Received close command, closing connection to peer."
          @io.close
        else
          raise Error.new("No implementation for command type #{command.class}")
        end
      end

      # Sends the handshake. Raises if one has already been sent.
      def send_handshake
        raise Error.new("Handshake already sent") if @handshake_sent
        @handshake_sent = true

        @log.debug "Sending handshake"

        # See `Torrent::Wire` documentation for an explanation of the handshake
        # packet flow.
        handshake = Protocol::Handshake.create(dht: @manager.use_dht?)
        @socket.write handshake.to_bytes                 # Step 1
        @socket.write transfer.info_hash                 # Step 2
        @socket.write transfer.peer_id.to_slice          # Step 3

        @log.debug "Waiting for handshake response..."
        handshake_sent.emit
        # Okay!
      end

      # Processes *data*. Note that this data must have come from the read
      # channel, else assumption made may be wrong and things will break.
      def handle_data(data : Bytes)
        @bytes_received += data.size

        if @state.packet_size?
          handle_packet_size(data)
        elsif @state.packet?
          handle_packet(data)
        else
          handle_handshake(data)
        end
      end

      def send_data(data : Bytes)
        preamble = Protocol::PacketSize.new(data.size.to_u32)

        packet = Bytes.new(sizeof(Wire::PacketSize) + data.size)
        packet.copy_from(preamble.to_bytes)
        (packet + sizeof(Wire::PacketSize)).copy_from(data)

        @bytes_sent += packet.size
        @io.write_later packet
      end

      def send_data(&block : -> Bytes?)
        @io.write_later(&block)
      end

      def send_packet(packet_id : UInt8, payload : Bytes? = nil)
        payload = payload.to_bytes if payload.responds_to?(:to_bytes)
        size = payload.try(&.size) || 0
        preamble = Protocol::PacketPreamble.new(
          id: packet_id,
          size: size.to_u32 + 1,
        )

        packet = Bytes.new(sizeof(Wire::PacketPreamble) + size)
        packet.copy_from(preamble.to_bytes)
        (packet + sizeof(Wire::PacketPreamble)).copy_from(payload) if payload

        @bytes_sent += packet.size
        @io.write_later packet
      end

      private def handle_handshake(data : Bytes)
        case @state
        when State::Connecting # Nothing
          set_state State::Handshake # Expect the handshake next
        when State::Handshake
          handshake = Protocol::Handshake.from(data)
          handshake.verify!

          @extension_protocol = handshake.extension_protocol?
          @fast_extension = handshake.fast_extension?

          @log.info "Peer supports extension protocol: #{@extension_protocol}"
          @log.info "Peer supports fast extensions: #{@fast_extension}"

          handshake_received.emit
          set_state State::InfoHash
        when State::InfoHash
          unless @manager.accept_info_hash?(data)
            raise Error.new("Unknown info hash: #{data.inspect}")
          end

          found = @manager.transfer_for_info_hash(data)
          if t = @transfer
            raise Error.new("Wrong info hash") if t != found
          end

          @transfer = found
          info_hash_received.emit(data)
          set_state State::PeerId
        when State::PeerId
          set_state State::PacketSize

          @remote_peer_id = data
          if data == transfer.peer_id.to_slice
            @log.error "Lets not connect to ourself"
            close
          end

          send_handshake unless handshake_sent?
          connection_ready.emit(data)

          if @extension_protocol
            @log.debug "Peer supports the extension protocol, sending handshake"
            @manager.extensions.send_handshake(self)
          end
        end
      end

      private def set_state(state, force = false)
        return if !force && state == @state

        @state = state
        case state
        when State::NotConnected # Nothing
        when State::Connecting # Nothing
        when State::Handshake
          @io.expect_block instance_sizeof(Wire::Handshake)
        when State::InfoHash
          @io.expect_block 20
        when State::PeerId
          @io.expect_block 20
        when State::PacketSize
          @io.expect_block sizeof(UInt32)
        when State::Packet
          # Callers responsibility to set the block size!
        end
      end

      private def handle_packet_size(data : Bytes)
        packet = Protocol::PacketSize.from(data)

        if packet.size == 0
          @log.debug "Received ping"
          set_state State::PacketSize, force: true
          ping_received.emit
        elsif packet.size > MAX_PACKET_SIZE
          @log.error "Peer tried to send packet of size #{packet.size} Bytes, but hard maximum is #{MAX_PACKET_SIZE} - Killing!"
          close
        else
          @io.expect_block packet.size
          set_state State::Packet
        end
      end

      private def handle_packet(data : Bytes)
        set_state State::PacketSize
        packet_id = data[0]
        payload = data + 1

        handle_packet packet_id, payload
      end
    end
  end
end
