module Torrent
  module Util
    # Wraps a `::Logger` so that we also have a context.
    class Logger
      getter context : String

      def initialize(@context : String)
      end

      def initialize(context)
        @context = Logger.format_context(context)
      end

      def context=(context : String)
        @context = context
      end

      def context=(context)
        @context = Logger.format_context(context)
      end

      {% for meth in %i[ debug info warn error fatal ] %}
        def {{ meth.id }}(message : String | Exception)
          sink = Torrent.logger
          return if sink.nil?

          message = format_exception(message) if message.is_a? Exception
          sink.{{ meth.id }}("[#{@context}] #{message}")
        end
      {% end %}

      private def format_exception(error)
        "#{error.class}: #{error.message}\n  #{error.backtrace.join("\n  ")}"
      end

      def self.format_context(context)
        "#{context.class}/0x#{pointerof(context).address.to_s 16}"
      end
    end
  end
end
