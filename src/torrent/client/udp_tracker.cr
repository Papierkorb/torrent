module Torrent
  module Client
    # Implements BEP-0015: UDP Tracker Protocol for BitTorrent.
    class UdpTracker < Tracker

      # Max wait time exponent
      MAX_N = 8

      # Max age of a connection_id cookie
      CONNECTION_TIMEOUT = 1.minute

      # Connection id used for "connect" requests.
      INITIAL_CONNECTION_ID = 0x41727101980u64

      # Connection cookie. See `#connection_cookie`.
      @connection_id : UInt64?

      # Builds a client for contacting the tracker at *url*
      def initialize(@url : URI)
        port = @url.port
        raise ArgumentError.new("URL does not specify port") if port.nil?

        @log = Util::Logger.new("Tracker/#{@url.host}")
        @socket = Util::UdpSocket.new
        @socket.connect @url.host.not_nil!, port
      end

      # Asks the tracker for peers of *transfer*.  Raises on error.
      def get_peers(transfer : Torrent::Transfer) : Array(Structure::PeerInfo)

        transaction = nil
        response, addresses = request_loop do |n|
          cookie = connection_cookie
          transaction = generate_transaction_id
          send_announce_request cookie, transaction, transfer
          recv_announce_response cookie, transaction, n
        end

        check_announce_response response, transaction

        list = read_address_port_list addresses
        @retry_interval = response.interval
        @last_request = Time.now
        list
      end

      # Returns statistics of the given *info_hashes*.  Raises on error.
      def scrape(info_hashes : Enumerable(Bytes)) : Structure::ScrapeResponse
        raise "Not implemented."
      end

      private def check_announce_response(response, transaction)
        if response.action != Wire::TrackerAction::Announce.value
          raise Error.new("Expected action 1, but got #{response.action}")
        end

        if response.transaction_id != transaction
          raise Error.new("Expected transaction #{transaction}, but got #{response.transaction_id}")
        end
      end

      private def read_address_port_list(buffer)
        raise Error.new("Buffer size #{buffer.size} is not divisible by 6") unless buffer.size.divisible_by? 6
        addresses, ports = split_address_buffer(buffer, buffer.size / 6)

        Array(Structure::PeerInfo).new(ports.size) do |idx|
          Structure::PeerInfo.new(
            address: addresses[idx * 4, 4].join("."),
            port: Util::Endian.to_host(ports[idx]).to_i32,
            v6: false,
          )
        end
      end

      private def split_address_buffer(buffer, count)
        port_off = count * sizeof(UInt32)
        addresses = buffer[0, port_off]
        ports = Slice(UInt16).new(buffer[port_off, count * 2].pointer(count * 2).as(UInt16*), count)
        { addresses, ports }
      end

      # Calculates the wait time for n in [0..MAX_N]
      private def wait_time(n)
        15 * (2 ** n.clamp(0, MAX_N))
      end

      # Generates a random transaction id
      private def generate_transaction_id : UInt32
        Random::DEFAULT.next_u
      end

      # Returns the current connection cookie.  If none has been requested yet,
      # or the old one has hit an time-out, a new one is acquired automatically.
      private def connection_cookie : UInt64
        cookie = @connection_id
        last = @last_request
        if cookie.nil? || (last && last + CONNECTION_TIMEOUT < Time.now)
          @connection_id = cookie = acquire_connection_cookie
        end

        cookie
      end

      # Tries to acquire a connection id cookie from the tracker.
      private def acquire_connection_cookie : UInt64
        request_loop do |n|
          transaction_id = generate_transaction_id
          send_connect_request transaction_id
          recv_connect_response transaction_id, n
        end
      end

      private def send_connect_request(transaction_id)
        @log.info "Sending CONNECT request"

        request = Protocol::TrackerConnectRequest.new(
          connection_id: INITIAL_CONNECTION_ID,
          action: Wire::TrackerAction::Connect.value,
          transaction_id: transaction_id,
        )

        send request.to_bytes
      end

      private def recv_connect_response(transaction_id, n)
        buf = recv(sizeof(Wire::TrackerConnectResponse), n)
        @log.info "Received CONNECT response with #{buf.size} Bytes"

        response = Protocol::TrackerConnectResponse.from(buf)
        if response.transaction_id != transaction_id
          raise Error.new("Received transaction_id #{response.transaction_id} is not the expected value #{transaction_id}")
        end

        if response.action != Wire::TrackerAction::Connect.value
          raise Error.new("Received action #{response.action}, but expected 0")
        end

        response.connection_id
      end

      private def send_announce_request(cookie, transaction_id, transfer)
        info_hash = StaticArray(UInt8, 20).new(0u8)
        peer_id = StaticArray(UInt8, 20).new(0u8)

        info_hash.to_slice.copy_from(transfer.info_hash)
        peer_id.to_slice.copy_from(transfer.peer_id.to_slice)

        @log.info "Sending ANNOUNCE request"
        request = Protocol::TrackerAnnounceRequest.new(
          connection_id: cookie,
          action: Wire::TrackerAction::Announce.value,
          transaction_id: transaction_id,
          info_hash: info_hash,
          peer_id: peer_id,
          downloaded: transfer.downloaded,
          left: transfer.left,
          uploaded: transfer.uploaded,
          event: transfer.status.value,
          ip_address: 0u32,
          key: 0u32,
          num_want: -1,
          port: transfer.manager.port.to_u16,
        )

        send build_bep41_announce_request(request.to_bytes)
      end

      private def build_bep41_announce_request(request)
        # TODO: If the full path is longer, we'd need to send multiple
        #       "URLData" options.
        path = @url.full_path[0, 0xFF].to_slice
        buffer = Bytes.new(request.size + 2 + path.size)

        buffer.copy_from(request)
        buffer[request.size] = 0x02u8
        buffer[request.size + 1] = path.size.to_u8
        path.copy_to(buffer + request.size + 2)
        buffer
      end

      private def recv_announce_response(cookie, transaction_id, n)
        buf = recv(sizeof(Wire::TrackerAnnounceResponse), n)
        @log.info "Received ANNOUNCE response with #{buf.size} Bytes"

        response = Protocol::TrackerAnnounceResponse.from(buf)
        { response, buf + sizeof(Wire::TrackerAnnounceResponse) }
      end

      private def request_loop
        (MAX_N + 1).times do |n|
          begin
            return yield n

            # Reraise the timeout only after the last try failed.
          rescue error : IO::Timeout
            @log.warn "Timeout, was try ##{n + 1}"
            raise error if n >= MAX_N
          end
        end

        raise "You can't end up here."
      end

      private def send(data)
        @socket.send data
      rescue error
        raise Error.new("Failed to send request: #{error}")
      end

      private def recv(byte_count, n) : Bytes
        buffer = Bytes.new Util::UdpSocket::MTU
        received = @socket.read(buffer, wait_time(n))

        if received < byte_count
          raise Error.new("Received too small datagram: #{received} < #{byte_count} Bytes")
        end

        buffer[0, received]
      end
    end
  end
end
