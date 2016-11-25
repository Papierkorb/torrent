module Torrent
  module Dht
    # Calls methods when invoked by remote nodes.
    class Dispatcher
      alias Method = Proc(Node, Structure::Query, Nil)

      # All methods the dispatcher knows about
      getter methods : Hash(String, Method)

      def initialize
        @methods = Hash(String, Method).new
        @log = Util::Logger.new("Dht/Dispatcher")
      end

      # Adds *method* to the dispatcher
      def add(method : String, func : Method)
        @methods[method] = func
      end

      # ditto
      def add(method : String, &block : Method)
        add method, block
      end

      # Invokes a method from *node* via *query*.  Returns `true` if the method
      # has been called, else `false` is returned.
      def invoke_method(node : Node, query : Structure::Query) : Bool
        func = @methods[query.method]?
        return false if func.nil?
        func.call node, query
        true
      end

      # Invokes *query* on behalf of *node*.  Sends an error response if the
      # called method was not found.
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
