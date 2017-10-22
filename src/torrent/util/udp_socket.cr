module Torrent
  module Util
    class UdpSocket < ::UDPSocket
      MTU = 1500

      def read(buffer, timeout)
        self.read_timeout = timeout
        read(buffer)
      end
    end
  end
end
