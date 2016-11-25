module Torrent
  module Dht
    # Error codes for `Node#send_error`
    enum ErrorCode : Int32

      # Generic error
      Generic = 201

      # An error was encountered while handling the otherwise valid packet
      Server = 202

      # The packet is invalid or otherwise malformed
      Protocol = 203

      # The called method is unknown
      MethodUnknown = 204

      def self.message(code : ErrorCode) : String
        case code
        when ErrorCode::Generic
          "A Generic Error Occured"
        when ErrorCode::Server
          "A Server Error Occured"
        when ErrorCode::Protocol
          "The Packet Was Malformed"
        when ErrorCode::MethodUnknown
          "The Called Method Is Unknown"
        else
          raise "#error_code_message is broken"
        end
      end
    end
  end
end
