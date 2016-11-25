module Torrent
  module Dht
    # DHT specific errors
    class Error < Torrent::Error
    end

    # Error during a `Node#remote_call!`
    class CallError < Error
    end

    # A call timed-out
    class CallTimeout < CallError
    end

    # A call returned an error
    class RemoteCallError < CallError
      getter data : Structure::Error

      def initialize(method, @data)
        super "Remote call error to #{method.inspect}: #{@data.code} - #{@data.message}"
      end
    end

    # An error in a DHT query handler.  Can be thrown to easily set the replied
    # error code and message.
    class QueryHandlerError < Error
      # The DHT error code
      getter code : Int32

      # The DHT error message
      getter public_message : String

      def initialize(@code : Int32, @public_message : String)
        super "#{@code}: #{@public_message}"
      end

      def initialize(code : ErrorCode, public_message : String? = nil)
        @code = code.value
        @public_message = public_message || ErrorCode.message(code)
        super "#{@code}: #{@public_message}"
      end

      def initialize(message, code : ErrorCode, public_message : String? = nil)
        @code = code.value
        @public_message = public_message || ErrorCode.message(code)
        super "#{message} (#{@code}: #{@public_message}"
      end

      def initialize(message, @code : Int32, @public_message : String)
        super "#{message} (#{@code}: #{@public_message}"
      end
    end
  end
end
