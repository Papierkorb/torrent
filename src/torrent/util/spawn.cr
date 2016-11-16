module Torrent
  module Util
    # Helper which returns the full name of the caller of the method which calls
    # this method.
    def self.caller_name(frames_up = 2) : String
      backtrace = caller
      idx = backtrace.size - 4 - frames_up
      line = backtrace[idx.clamp(0, backtrace.size - 1)]

      off = line.index(' ')
      return line if off.nil?

      off += 1
      off += 1 if line[off] == '*'

      bracket = line.index('<', off)

      return line[off..-1] if bracket.nil?
      line[off...bracket]
    end

    # Spawns the given block in a new fiber.  The fiber is automatically named
    # based on the caller of this method.  If the fiber crashes, it's logged to
    # `Torrent.logger`, and if *fatal* is `true` (Which is the default), the
    # program is ended through `exit`.
    def self.spawn(name : String = caller_name, fatal = true, &block)
      ::spawn(name: name) do
        begin
          block.call
        rescue error
          log = Logger.new("Fiber")
          log.error "Uncaught error in fiber #{Fiber.current}"
          log.error error

          exit 1 if fatal
        end
      end
    end
  end
end
