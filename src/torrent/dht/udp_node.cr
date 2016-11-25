module Torrent
  module Dht
    class UdpNode < Node

      getter local_address : Socket::IPAddress
      getter remote_address : Socket::IPAddress

      def initialize(@socket : Util::UdpSocket, @remote_address : Socket::IPAddress, @owns_socket = false)
        super(-1.to_big_i)
        @local_address = @socket.local_address

        @running = true
        @log.context = "Node/#{@remote_address}"
        Util.spawn("DHT-UDP/#{@remote_address}"){ start_receiving_data } if @owns_socket
      end

      def close
        @running = false
        @socket.close if @owns_socket
        super
      end

      def send(message : Structure::Message)
        datagram = message.to_bencode
        @socket.send datagram, @remote_address
      rescue error
        raise Error.new("Failed to send message: #{error}")
      end

      private def start_receiving_data
        while @running
          datagram = do_receive
          handle_incoming datagram if datagram
        end
      rescue error
        @log.error "Error occured while reading data."
        @log.error error
        close
      end

      private def do_receive
        buf = Bytes.new(Util::UdpSocket::MTU)
        bytes = @socket.read(buf)
        buf[0, bytes]
      end
    end
  end
end
