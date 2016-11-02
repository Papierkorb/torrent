module Torrent
  module FileManager
    # Manages a transfer directory in the file system.
    class FileSystem < FileManager::Base
      HANDLE_CACHE_SIZE = 100

      # Base path of the transfer directory
      getter base_path : String

      def initialize(base_path)
        if base_path.ends_with? '/'
          @base_path = base_path
        else
          @base_path = base_path + '/'
        end

        @handle_cache = Hash(String, IO::FileDescriptor).new
      end

      def read_file(file_path : String, offset, buffer : Bytes) : Nil
        io = get_handle(file_path)
        io.seek offset
        io.read_fully buffer
      end

      def write_file(file_path : String, offset, buffer : Bytes) : Nil
        io = get_handle(file_path)
        io.seek offset
        io.write buffer
        io.flush
      end

      private def get_handle(path)
        long_path = full_path(path)
        handle = @handle_cache[long_path]?

        if handle.nil?
          if @handle_cache.size > HANDLE_CACHE_SIZE
            _path, to_close = @handle_cache.shift
            to_close.close
          end

          handle = open_for_write(long_path)
          @handle_cache[long_path] = handle
        end

        handle
      end

      private def open_for_write(full_path : String)
        flags = LibC::O_RDWR | LibC::O_CLOEXEC | LibC::O_CREAT
        perm = ::File::DEFAULT_CREATE_MODE

        Dir.mkdir_p ::File.dirname(full_path)
        fd = LibC.open(full_path, flags, perm)
        IO::FileDescriptor.new(fd, blocking: true)
      end

      private def full_path(path : String) : String
        @base_path + check_path(path)
      end

      private def check_path(path : String) : String
        path.check_no_null_byte

        if path.starts_with?("../") || path.ends_with?("/..") || path.includes?("/../") || path == ".."
          raise "Illegal file path: #{path.inspect}"
        end

        if path.starts_with?('/')
          path[1..-1]
        else
          path
        end
      end
    end
  end
end
