require "../../spec_helper"

private def bitfield(*bytes)
  data = Bytes.new bytes.size do |idx|
    bytes[idx].to_u8
  end

  Torrent::Util::Bitfield.new(data)
end

describe "Torrent::Util::Bitfield" do
  describe ".bytesize" do
    it "returns the bytes needed" do
      Torrent::Util::Bitfield.bytesize(32).should eq 4
      Torrent::Util::Bitfield.bytesize(33).should eq 5
    end
  end

  describe "#clone" do
    it "deep-copies the data" do
      original = bitfield(0x11, 0x22)
      copy = original.clone
      original.to_bytes.pointer(0).should_not eq(copy.to_bytes.pointer(0))
    end
  end

  describe "#size" do
    it "returns the count of bits" do
      bitfield(1, 2, 3, 4, 5).size.should eq 40
    end
  end

  describe "#all_ones?" do
    it "returns true" do
      bitfield(0xFF).all_ones?.should be_true
      bitfield(0xFF, 0xFF, 0xFF, 0xFF).all_ones?.should be_true
      bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF).all_ones?.should be_true
      bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF).all_ones?.should be_true
      bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF).all_ones?.should be_true
    end

    it "returns false" do
      bitfield(0xEF).all_ones?.should be_false
      bitfield(0xFF, 0xEF).all_ones?.should be_false
      bitfield(0xFF, 0xEF, 0xFF).all_ones?.should be_false
      bitfield(0xFF, 0xEF, 0xFF, 0xFF).all_ones?.should be_false
      bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF, 0xFF).all_ones?.should be_false
      bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF).all_ones?.should be_false
    end
  end

  describe "#all_zero?" do
    it "returns true" do
      bitfield(0).all_zero?.should be_true
      bitfield(0, 0, 0, 0).all_zero?.should be_true
      bitfield(0, 0, 0, 0, 0, 0, 0, 0, 0).all_zero?.should be_true
      bitfield(0, 0, 0, 0, 0, 0, 0, 0, 0, 0).all_zero?.should be_true
      bitfield(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0).all_zero?.should be_true
    end

    it "returns false" do
      bitfield(1).all_zero?.should be_false
      bitfield(0, 1).all_zero?.should be_false
      bitfield(0, 1, 0).all_zero?.should be_false
      bitfield(0, 1, 0, 0).all_zero?.should be_false
      bitfield(0, 0, 0, 0, 1, 0, 0, 0, 0).all_zero?.should be_false
      bitfield(0, 0, 0, 0, 0, 1, 0, 0, 0).all_zero?.should be_false
      bitfield(0, 0, 0, 0, 0, 0, 1, 0, 0).all_zero?.should be_false
      bitfield(0, 0, 0, 0, 0, 0, 0, 1, 0).all_zero?.should be_false
      bitfield(0, 0, 0, 0, 0, 0, 0, 0, 1).all_zero?.should be_false
    end
  end

  describe "#all?" do
    it "handles non-full-byte sizes" do
      bits = Torrent::Util::Bitfield.new(64 + 8 + 2, 0xFFu8)
      bits.all?(true).should be_true

      bits[64 + 8 + 1] = false
      bits.all?(true).should be_false
    end
  end

  describe "#[]" do
    it "returns true" do
      bitfield(0x02)[6].should be_true
      bitfield(0x00, 0x02)[14].should be_true
    end

    it "returns false" do
      bitfield(0xEF)[3].should be_false
      bitfield(0xFF, 0xFE)[15].should be_false
    end
  end

  describe "#[]=" do
    it "sets a bit" do
      bits = bitfield(0x00)
      bits[1] = true
      bits.to_bytes.should eq Bytes[ 0x40u8 ]

      bits = bitfield(0x00, 0x00)
      bits[9] = true
      bits.to_bytes.should eq Bytes[ 0x00, 0x40u8 ]
    end

    it "clears a bit" do
      bits = bitfield(0xFF)
      bits[1] = false
      bits.to_bytes.should eq Bytes[ 0xBFu8 ]

      bits = bitfield(0xFF, 0xFF)
      bits[9] = false
      bits.to_bytes.should eq Bytes[ 0xFF, 0xBFu8 ]
    end
  end

  describe "#find_random_unset" do
    it "finds a random unset bit" do
      data = Bytes.new 402, 0x11u8
      bits = Torrent::Util::Bitfield.new(data)

      chosen = Array(Int32).new(1000) do
        bits.find_random_unset.not_nil!
      end

      # Not everyone should be the same.
      chosen.all?{|cur| cur == chosen.first}.should be_false
    end

    it "finds the one last clear bit (trailing part)" do
      data = Bytes.new 402, 0xFFu8
      data[401] = 0xFEu8

       Torrent::Util::Bitfield.new(data).find_random_unset.should eq(401 * 8)
     end

     it "finds the one last clear bit (main part)" do
      data = Bytes.new 402, 0xFFu8
      data[200] = 0xEFu8

       Torrent::Util::Bitfield.new(data).find_random_unset.should eq(200 * 8 + 4)
    end
  end

  describe "#find_next_unset" do
    it "finds the next unset bit" do
      data = Bytes.new 23, 0xFFu8
      bits = Torrent::Util::Bitfield.new(data)

      data.each_with_index do |_el, idx|
        8.times do |bit|
          data[idx] &= ~(1 << bit)
          bits.find_next_unset.should eq (idx * 8 + bit)
          data[idx] |= 1 << bit
        end
      end
    end
  end

  describe "#count" do
    it "counts set bits" do
      bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF, 0xFC).count(true).should eq(69)
    end

    it "counts clear bits" do
      bitfield(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF, 0xFC).count(false).should eq(3)
    end
  end

  describe "#each(Bool)" do
    it "yields each true bit index" do
      expected = [ 0, 5, 15 ]

      bitfield(0x84, 0x01).each(true) do |idx|
        expected.delete(idx)
      end

      expected.empty?.should be_true
    end

    it "yields each false bit index" do
      expected = [ 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14 ]

      bitfield(0x84, 0x01).each(false) do |idx|
        expected.delete(idx)
      end

      expected.empty?.should be_true
    end
  end
end
