require "../../spec_helper"

private def bitfield(*bytes)
  data = Bytes.new bytes.size do |idx|
    bytes[idx].to_u8
  end

  Torrent::Util::Bitfield.new(data)
end

Spec2.describe "Torrent::Util::Bitfield" do
  describe ".bytesize" do
    it "returns the bytes needed" do
      expect(Torrent::Util::Bitfield.bytesize(32)).to eq 4
      expect(Torrent::Util::Bitfield.bytesize(33)).to eq 5
    end
  end

  describe "#clone" do
    it "deep-copies the data" do
      original = bitfield(0x11, 0x22)
      copy = original.clone
      expect(original.to_bytes.pointer(0)).not_to eq(copy.to_bytes.pointer(0))
    end
  end

  describe "#size" do
    it "returns the count of bits" do
      expect(bitfield(1, 2, 3, 4, 5).size).to eq 40
    end
  end

  describe "#all_ones?" do
    it "returns true" do
      expect(bitfield(0xFF).all_ones?).to be_true
      expect(bitfield(0xFF, 0xFF, 0xFF, 0xFF).all_ones?).to be_true
      expect(bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF).all_ones?).to be_true
      expect(bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF).all_ones?).to be_true
      expect(bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF).all_ones?).to be_true
    end

    it "returns false" do
      expect(bitfield(0xEF).all_ones?).to be_false
      expect(bitfield(0xFF, 0xEF).all_ones?).to be_false
      expect(bitfield(0xFF, 0xEF, 0xFF).all_ones?).to be_false
      expect(bitfield(0xFF, 0xEF, 0xFF, 0xFF).all_ones?).to be_false
      expect(bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF, 0xFF).all_ones?).to be_false
      expect(bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF).all_ones?).to be_false
    end
  end

  describe "#all_zero?" do
    it "returns true" do
      expect(bitfield(0).all_zero?).to be_true
      expect(bitfield(0, 0, 0, 0).all_zero?).to be_true
      expect(bitfield(0, 0, 0, 0, 0, 0, 0, 0, 0).all_zero?).to be_true
      expect(bitfield(0, 0, 0, 0, 0, 0, 0, 0, 0, 0).all_zero?).to be_true
      expect(bitfield(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0).all_zero?).to be_true
    end

    it "returns false" do
      expect(bitfield(1).all_zero?).to be_false
      expect(bitfield(0, 1).all_zero?).to be_false
      expect(bitfield(0, 1, 0).all_zero?).to be_false
      expect(bitfield(0, 1, 0, 0).all_zero?).to be_false
      expect(bitfield(0, 0, 0, 0, 1, 0, 0, 0, 0).all_zero?).to be_false
      expect(bitfield(0, 0, 0, 0, 0, 1, 0, 0, 0).all_zero?).to be_false
      expect(bitfield(0, 0, 0, 0, 0, 0, 1, 0, 0).all_zero?).to be_false
      expect(bitfield(0, 0, 0, 0, 0, 0, 0, 1, 0).all_zero?).to be_false
      expect(bitfield(0, 0, 0, 0, 0, 0, 0, 0, 1).all_zero?).to be_false
    end
  end

  describe "#all?" do
    it "handles non-full-byte sizes" do
      bits = Torrent::Util::Bitfield.new(64 + 8 + 2, 0xFFu8)
      expect(bits.all?(true)).to be_true

      bits[64 + 8 + 1] = false
      expect(bits.all?(true)).to be_false
    end
  end

  describe "#[]" do
    it "returns true" do
      expect(bitfield(0x02)[6]).to be_true
      expect(bitfield(0x00, 0x02)[14]).to be_true
    end

    it "returns false" do
      expect(bitfield(0xEF)[3]).to be_false
      expect(bitfield(0xFF, 0xFE)[15]).to be_false
    end
  end

  describe "#[] assignment" do
    it "sets a bit" do
      bits = bitfield(0x00)
      bits[1] = true
      expect(bits.to_bytes).to eq Slice[ 0x40u8 ]

      bits = bitfield(0x00, 0x00)
      bits[9] = true
      expect(bits.to_bytes).to eq Slice[ 0x00u8, 0x40u8 ]
    end

    it "clears a bit" do
      bits = bitfield(0xFF)
      bits[1] = false
      expect(bits.to_bytes).to eq Slice[ 0xBFu8 ].as(Bytes)

      bits = bitfield(0xFF, 0xFF)
      bits[9] = false
      expect(bits.to_bytes).to eq Slice[ 0xFFu8, 0xBFu8 ].as(Bytes)
    end
  end

  describe "#find_next_unset" do
    it "finds the next unset bit" do
      data = Bytes.new 23, 0xFFu8
      bits = Torrent::Util::Bitfield.new(data)

      data.each_with_index do |_el, idx|
        8.times do |bit|
          data[idx] &= ~(1 << bit)
          expect(bits.find_next_unset).to eq (idx * 8 + bit)
          data[idx] |= 1 << bit
        end
      end
    end
  end

  describe "#count" do
    it "counts set bits" do
      expect(bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF, 0xFC).count(true)).to eq(69)
    end

    it "counts clear bits" do
      expect(bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF, 0xFC).count(false)).to eq(3)
    end
  end

  describe "#each(Bool)" do
    it "yields each true bit index" do
      expected = [ 0, 5, 15 ]

      bitfield(0x84, 0x01).each(true) do |idx|
        expected.delete(idx)
      end

      expect(expected.empty?).to be_true
    end

    it "yields each false bit index" do
      expected = [ 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14 ]

      bitfield(0x84, 0x01).each(false) do |idx|
        expected.delete(idx)
      end

      expect(expected.empty?).to be_true
    end
  end
end
