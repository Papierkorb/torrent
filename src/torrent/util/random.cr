module Torrent
  module Util
    module Random
      # Returns *count* random bytes.
      def self.bytes(count, random = ::Random::DEFAULT)
        Bytes.new(count){ random.rand(0..0xFF).to_u8 }
      end
    end
  end
end
