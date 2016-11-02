module Torrent
  module Util
    class AsyncIoChannel
      BUFFER_SIZE = IO::Buffered::BUFFER_SIZE

      # The wrapped IO
      getter io : IO

      # Emitted when an error occures
      Cute.signal error_occured(error : Exception)

      # The read channel. Received data will be sent into this channel.
      getter read_channel : Channel(Bytes)

      # The write channel. Data sent into this channel will be written into the IO.
      getter write_channel : Channel::Buffered(Bytes | Proc(Bytes?) | Nil)

      @next_block : Bytes?
      @block_pos : Int32 = 0

      def initialize(@io : IO)
        @read_channel = Channel(Bytes).new
        @write_channel = Channel::Buffered(Bytes | Proc(Bytes?) | Nil).new
      end

      # The next channel message will have the required *size*.
      # This method is only valid for the **next** message, after that the
      # expectation will be unset.
      def expect_block(size : Int) : Nil
        @next_block = Bytes.new(size.to_i32)
        @block_pos = 0
      end

      # Will spawn a fiber to read on the given *io* and send received data
      # through the returned channel.
      def start
        Util.spawn do
          log = Util::Logger.new(self)
          with_rescue "reading" do
            loop do
              buffer = do_read
              # log.debug "-> #{buffer.try &.hexstring}"
              @read_channel.send buffer if buffer
            end
          end
        end

        Util.spawn do
          log = Util::Logger.new(self)
          with_rescue "writing" do
            loop do
              data = @write_channel.receive
              break if data.nil?
              data = data.call if data.is_a?(Proc)
              # log.debug "<- #{data.try &.hexstring}"
              @io.write data if data.is_a?(Bytes)
            end
          end
        end
      end

      # Closes the inner IO and stops all fibers
      def close
        @write_channel.send nil
        @io.close
      end

      # Sends *data* into the write channel for it to be sent.
      def write_later(data : Bytes)
        @write_channel.send(data)
      end

      # Sends the block into the channel. The block will be called to get the
      # data to be sent when it's scheduled to be sent. If the block returns
      # *nil*, then nothing will be sent.
      def write_later(&block : -> Bytes?)
        @write_channel.send(block)
      end

      private def do_read : Bytes?
        if block = @next_block
          read_size = @io.read(block + @block_pos)
          raise IO::EOFError.new if read_size < 1

          @block_pos += read_size
          return nil unless @block_pos == block.size

          # Done reading the block
          @block_pos = 0
          @next_block = nil
          block
        else
          buffer = Bytes.new(BUFFER_SIZE)
          read_size = @io.read(buffer)
          buffer[0, read_size]
        end
      end

      private def with_rescue(action)
        yield
      rescue error
        error_occured.emit(error)
        close
      end
    end
  end
end
