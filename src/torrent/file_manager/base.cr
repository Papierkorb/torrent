module Torrent
  module FileManager
    # Manages a transfer directory. This is the "download" directory, where
    # downloaded files will be stored and read from.
    #
    # Feel free to reimplement this class to store downloads in a database or so.
    #
    # **Important note**:
    # Treat the *file_path* argument to methods as user input. This means, you
    # have to make sure that it is "sane" with regards to your implementation.
    # A common attack vector is "Directory Traversal", where the file path could
    # be a absolute path or a relative path using ".." to break out of a base
    # directory.
    abstract class Base

      # Reads *buffer.size* bytes into *buffer* from *file_path* at offset
      # *offset*. Raises `Errno` if file is not found.
      abstract def read_file(file_path : String, offset, buffer : Bytes) : Nil

      # Writes *buffer.size* bytes from *buffer* into *file_path* at *offset*.
      #
      # If the file already exists, it is **not** truncated. If the file does
      # not exist, it will be created. If the path leading to the file (its
      # parent directories) does not exist, they're automatically created.
      abstract def write_file(file_path : String, offset, buffer : Bytes) : Nil
    end
  end
end
