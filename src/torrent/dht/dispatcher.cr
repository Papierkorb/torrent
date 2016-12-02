module Torrent
  module Dht
    # RPC dispatcher used to call named methods on behalf of remote nodes.
    class Dispatcher

      # Function handler used by `Dispatcher#add`.
      # See `Dispatcher#add` for further information.
      alias Method = Proc(Node, Structure::Query, Nil)

      # All methods the dispatcher knows about
      getter methods : Hash(String, Method)

      def initialize
        @methods = Hash(String, Method).new
        @log = Util::Logger.new("Dht/Dispatcher")
      end

      # Adds *method* to the dispatcher.  The *func* is called whenever a
      # request comes in for *method*.  The *func* shall then do the required
      # work, and send a response through `Node#send` by itself.
      #
      # If the *func* raises an exception, an error response is automatically
      # sent to the remote node.  See `QueryHandlerError` to modify the sent
      # error data.  Every other exception is signaled as server error.
      #
      # See also `Structure::Query#response` and `Structure::Query#error` to
      # easily build response messages out of the passed query in *func*.
      def add(method : String, func : Method)
        @methods[method] = func
      end

      # ditto
      def add(method : String, &block : Method)
        add method, block
      end

      # Invokes a method from *node* via *query*.  Returns `true` if the method
      # has been called, else `false` is returned.
      #
      # **Note**: This method does not catch exceptions by itself.  In general,
      # you'll probably want to use `#remote_invocation` over this method.
      def invoke_method(node : Node, query : Structure::Query) : Bool
        func = @methods[query.method]?
        return false if func.nil?
        func.call node, query
        true
      end

      # Invokes *query* on behalf of *node*.  Sends an error response if the
      # called method was not found.  Returns `true` on success, or `false` if
      # no method for *query* was found or if the called handler raised an
      # exception.
      #
      # **Warning**: If the handler sends an error response by itself but does
      # not raise, the method returns `true`.
      def remote_invocation(node : Node, query : Structure::Query) : Bool
        result = invoke_method node, query

        unless result
          @log.error "Node #{node.remote_address} invoked unknown method #{query.method.inspect} with #{query.args.size} arguments"
          node.send query.error(ErrorCode::MethodUnknown)
        end

        result
      rescue error
        @log.error "Error while handling invocation of #{query.method.inspect}: (#{error.class}) #{error}"
        @log.error error

        if error.is_a? QueryHandlerError
          node.send query.error(error.code, error.public_message)
        else
          node.send query.error(ErrorCode::Server)
        end

        false
      end
    end
  end
end
