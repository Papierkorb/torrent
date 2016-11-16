@[Link("gmp")]
lib LibGMP
  # mpz_export (void *rop, size_t *countp, int order, size_t size, int endian, size_t nails, const mpz_t op)
  fun export = __gmpz_export(rop : Void*, countp : LibC::SizeT*, order : Int32, size : LibC::SizeT, endian : Int32, nails : LibC::SizeT, op : MPZ*) : Void*

  # void mpz_import (mpz_t rop, size_t count, int order, size_t size, int endian, size_t nails, const void *op)
  fun import = __gmpz_import(rop : MPZ*, count : LibC::SizeT, order : Int32, size : LibC::SizeT, endian : Int32, nails : LibC::SizeT, op : Void*) : Void
end

module Torrent
  module Util
    # `BigInt` import and export functionality.  For documentation of the
    # arguments, please see:
    # https://gmplib.org/manual/Integer-Import-and-Export.html
    module Gmp
      SHA1_LEN = 20

      def self.export(integer : BigInt, order : Int32, size : Int32, endian : Int32, nails : Int32) : Bytes
        ptr = LibGMP.export(
          nil,
          out length,
          order,
          LibC::SizeT.new(size),
          endian,
          LibC::SizeT.new(nails),
          integer.to_unsafe
        )

        Bytes.new(ptr.as(UInt8*), length)
      end

      def self.import(bytes : Bytes, order : Int32, size : Int32, endian : Int32, nails : Int32) : BigInt
        mpz = LibGMP::MPZ.new

        LibGMP.import(
          pointerof(mpz),
          bytes.size,
          order,
          LibC::SizeT.new(size),
          endian,
          LibC::SizeT.new(nails),
          bytes.pointer(bytes.size).as(Void*)
        )

        BigInt.new(mpz)
      end

      # Exports a zero-padded SHA-1 byte-string in network byte order
      def self.export_sha1(integer : BigInt) : Bytes
        exported = export integer, 1, 1, 1, 0

        return exported if exported.size == SHA1_LEN
        raise IndexError.new("Integer too large") if exported.size > SHA1_LEN

        # Pad to 20 bytes
        bytes = Bytes.new(SHA1_LEN, 0u8)
        (bytes + (SHA1_LEN - exported.size)).copy_from exported
        bytes
      end

      # Imports a SHA-1 byte-string in network byte order
      def self.import_sha1(bytes : Bytes) : BigInt
        raise IndexError.new("Integer too large") if bytes.size > SHA1_LEN
        import bytes, 1, 1, 1, 0
      end
    end
  end
end
