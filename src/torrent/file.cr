module Torrent
  class File

    # Reads a .torrent file at *file_path*
    def self.from_file(file_path) : self
      File.open(file_path, "r"){|h| new h}
    end

    # List of all files
    getter files : Array(Structure::SingleFileInfo)

    # Wrapped data structure
    getter meta : Structure::MetaInfo

    # Reads the .torrent file from the *buffer*.
    def initialize(buffer : Bytes)
      @meta = Structure::MetaInfo.from_bencode(buffer)
      info = @meta.info

      range = info.raw_range.not_nil! # Is set at this point
      info.raw_data = buffer[range.begin, range.end - range.begin]

      if files = info.files
        @files = files
      elsif length = info.length
        @files = [ Structure::SingleFileInfo.new(info.name, length) ]
      else
        raise Error.new("Torrent file is neither a single-file nor multi-file one")
      end
    end

    # Reads a `File` from *file_path*
    def self.read(file_path)
      buf = Bytes.new ::File.size(file_path)
      ::File.open(file_path){|h| h.read_fully buf}
      Torrent::File.new(buf)
    end

    # Returns the list of announcing trackers for this torrent
    def announce_list
      @meta.announce_list || [ @meta.announce ]
    end

    # Returns the total size of all files in the torrent in Bytes
    def total_size
      @files.map(&.length).sum
    end

    # Returns the name of the torrent
    def name
      @meta.info.name
    end

    delegate created_by, created_at, to: @meta

    # Is this a private torrent? (As defined in BEP-0027)
    def private?
      @meta.private
    end

    # Returns the size of a piece (Size of a file block) in Bytes
    def piece_size
      @meta.info.piece_length
    end

    # Returns the count of pieces in this torrent
    def piece_count
      @meta.info.pieces.size
    end

    # Returns the SHA-1 hashsums of this torrent
    def sha1_sums
      @meta.info.pieces
    end

    # Calculates the `info hash`
    getter info_hash : Bytes do
      digest = Digest::SHA1.digest @meta.info.raw_data.not_nil!

      # `digest` is stored on the stack, so if we'd do #to_slice, we'd get a
      # slice pointing into our stack, and thus will get destroyed after we
      # leave this method.  Thus, we copy that thing into the heap.
      Bytes.new(20).tap do |buf|
        buf.copy_from(digest.to_slice)
      end
    end

    # Decodes the *piece* index with the length into a list of file paths
    # and inner offsets.
    def decode_piece_to_paths(piece : Int, offset, length)
      raise Error.new("Piece index #{piece} is out of bounds: 0...#{piece_count}") if piece < 0 || piece >= piece_count

      byte_offset = piece_size * piece + offset
      file_idx, file_offset = file_at_offset(byte_offset)

      result = Array(Tuple(String, UInt64, UInt64)).new
      while length > 0
        file = @files[file_idx]?
        file_idx += 1
        break if file.nil?
        next if file.length == 0

        inner_length = Math.min(length, file.length - file_offset)
        result << { file.path, file_offset.to_u64, inner_length.to_u64 }

        file_offset = 0
        length -= inner_length
      end

      if length > 0
        raise Error.new("Can't decode block at piece #{piece} length #{length}: End position outside any torrent file")
      end

      result
    end

    private def file_at_offset(byte_offset : UInt64)
      offset = 0u64

      @files.each_with_index do |current, idx|
        next_offset = offset + current.length

        if byte_offset < next_offset
          return { idx, byte_offset - offset }
        end

        offset = next_offset
      end

      raise Error.new("Byte offset #{byte_offset} is greater than torrent size")
    end
  end
end
