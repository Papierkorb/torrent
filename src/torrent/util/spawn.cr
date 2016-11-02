module Torrent
  module Util
    def self.spawn(&block)
      ::spawn do
        begin
          block.call
        rescue error
          log = Logger.new("Fiber")
          log.error "Uncaught error in fiber #{Fiber.current}"
          log.error error

          exit 1
        end
      end
    end
  end
end
