module Torrent
  module Util
    class UdpSocket < ::UDPSocket
      MTU = 1500

      def read(buffer, timeout)
        result = IO.select([ self ], nil, [ self ], timeout)

        raise IO::Timeout.new("No data received after #{timeout} seconds") if result.nil?

        read(buffer)
      end
    end
  end
end
