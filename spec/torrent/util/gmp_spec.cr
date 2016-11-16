require "../../spec_helper"

Spec2.describe Torrent::Util::Gmp do
  let(:bytes) do
    Slice[
      0x11u8, 0x22u8, 0x33u8, 0x44u8, 0x55u8,
      0x66u8, 0x77u8, 0x88u8, 0x99u8, 0x00u8,
      0x11u8, 0x22u8, 0x33u8, 0x44u8, 0x55u8,
      0x66u8, 0x77u8, 0x88u8, 0x99u8, 0x00u8
    ]
  end

  let(:bigint) do
    BigInt.new "97815534420055201845582779189627195583443278080"
  end

  describe ".export_sha1" do
    it "exports the BigInt" do
      expect(Torrent::Util::Gmp.export_sha1 bigint).to eq bytes
    end

    context "if the number is too big" do
      it "raises IndexError" do
        expect{ Torrent::Util::Gmp.export_sha1 2.to_big_i ** 160 }.to raise_error(IndexError)
      end
    end

    context "if the number is too small" do
      it "pads to 20 bytes" do
        expect(Torrent::Util::Gmp.export_sha1 0x11.to_big_i).to eq Slice [
          0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8,
          0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8,
          0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8,
          0x00u8, 0x00u8, 0x00u8, 0x00u8, 0x11u8
        ]
      end
    end
  end

  describe ".import_sha1" do
    it "imports the BigInt" do
      expect(Torrent::Util::Gmp.import_sha1 bytes).to eq bigint
    end

    context "if the number is too big" do
      it "raises IndexError" do
        huge = Bytes.new(21, 0u8)
        huge[0] = 0x01u8

        expect{ Torrent::Util::Gmp.import_sha1 huge }.to raise_error(IndexError)
      end
    end
  end

  describe "sanity check" do
    it "can import the exported data" do
      data = Torrent::Util::Gmp.export_sha1 bigint
      expect(Torrent::Util::Gmp.import_sha1 data).to eq bigint
    end
  end
end
