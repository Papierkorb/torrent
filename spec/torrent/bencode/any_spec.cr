require "../../spec_helper"

private def any(code)
  Torrent::Bencode.load(code.to_slice)
end

Spec2.describe Torrent::Bencode::Any do
  describe "#object" do
    it "returns the integer on an integer" do
      expect(any("i5e").object).to eq 5i64
    end

    it "returns the slice on a byte string" do
      expect(any("4:okay").object).to eq "okay".to_slice
    end

    it "returns the array on an array" do
      expect(any("li3ee").object).to eq([ any("i3e") ])
    end

    it "returns the hash on a hash" do
      expect(any("d3:fooi8ee").object).to eq({ "foo" => any("i8e") })
    end
  end

  describe "#to_i" do
    it "returns the integer on an integer" do
      expect(any("i5e").to_i).to eq 5i64
    end

    it "fails on a byte string" do
      expect{ any("4:okay").to_i }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "fails on an array" do
      expect{ any("li3ee").to_i }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "fails on a hash" do
      expect{ any("d3:fooi8ee").to_i }.to raise_error(Torrent::Bencode::Any::Error)
    end
  end

  describe "#to_s" do
    it "returns the integer on an integer" do
      expect(any("i5e").to_s).to eq 5i64.to_s
    end

    it "returns the string on a byte string" do
      expect(any("4:okay").to_s).to eq "okay".to_s
    end

    it "returns the array on an array" do
      expect(any("li3ee").to_s).to eq([ any("i3e") ].to_s)
    end

    it "returns the hash on a hash" do
      expect(any("d3:fooi8ee").to_s).to eq({ "foo" => any("i8e") }.to_s)
    end
  end

  describe "#to_a" do
    it "fails on an integer" do
      expect{ any("i5e").to_a }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "fails on a byte string" do
      expect{ any("4:okay").to_a }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "returns the array on an array" do
      expect(any("li3ee").to_a).to eq [ any("i3e") ]
    end

    it "fails on a hash" do
      expect{ any("d3:fooi8ee").to_a }.to raise_error(Torrent::Bencode::Any::Error)
    end
  end

  describe "#to_h" do
    it "fails on an integer" do
      expect{ any("i5e").to_h }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "fails on a byte string" do
      expect{ any("4:okay").to_h }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "fails on an array" do
      expect{ any("li3ee").to_h }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "returns the hash on a hash" do
      expect(any("d3:fooi8ee").to_h).to eq({ "foo" => any("i8e") })
    end
  end

  describe "#to_b" do
    it "returns true for a non-zero integer" do
      expect(any("i1e").to_b).to be_true
    end

    it "returns false for a non-zero integer" do
      expect(any("i0e").to_b).to be_false
    end

    it "fails for anything but an integer" do
      expect{ any("4:okay").to_b }.to raise_error(Torrent::Bencode::Any::Error)
      expect{ any("li3ee").to_b }.to raise_error(Torrent::Bencode::Any::Error)
      expect{ any("d3:fooi8ee").to_b }.to raise_error(Torrent::Bencode::Any::Error)
    end
  end

  describe "#size" do
    it "fails on an integer" do
      expect{ any("i5e").size }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "returns the size on a byte string" do
      expect(any("4:okay").size).to eq 4
    end

    it "returns the size on an array" do
      expect(any("li3ee").size).to eq 1
    end

    it "returns the size on a hash" do
      expect(any("d3:fooi8ee").size).to eq 1
    end
  end

  describe "#[]" do
    it "fails on an integer" do
      expect{ any("i5e")[0] }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "fails on a byte string" do
      expect{ any("3:foo")[0] }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "works on an array in-bounds" do
      expect(any("li3ee")[0]).to eq any("i3e")
    end

    it "works on a hash if the key is found" do
      expect(any("d3:fooi8ee")["foo"]).to eq any("i8e")
    end

    it "fails on an array out-of-bounds" do
      expect{ any("li3ee")[1] }.to raise_error(IndexError)
    end

    it "fails on a hash if the key is NOT found" do
      expect{ any("d3:fooi8ee")["bar"] }.to raise_error(KeyError)
    end
  end

  # See https://github.com/waterlink/spec2.cr/issues/46
  describe "#[] question" do
    it "fails on an integer" do
      expect{ any("i5e")[0]? }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "fails on a byte string" do
      expect{ any("3:foo")[0]? }.to raise_error(Torrent::Bencode::Any::Error)
    end

    it "works on an array in-bounds" do
      expect(any("li3ee")[0]?).to eq any("i3e")
    end

    it "works on a hash if the key is found" do
      expect(any("d3:fooi8ee")["foo"]?).to eq any("i8e")
    end

    it "returns nil on an array out-of-bounds" do
      expect(any("li3ee")[1]?).to be_nil
    end

    it "returns nil on a hash if the key is NOT found" do
      expect(any("d3:fooi8ee")["bar"]?).to be_nil
    end
  end

  describe "#to_bencode" do
    it "returns the bencode data for an integer" do
      expect(any("i5e").to_bencode).to eq "i5e".to_slice
    end

    it "returns the bencode data for a byte string" do
      expect(any("4:okay").to_bencode).to eq "4:okay".to_slice
    end

    it "returns the bencode data for an array" do
      expect(any("li3ee").to_bencode).to eq "li3ee".to_slice
    end

    it "returns the bencode data for a hash" do
      expect(any("d3:fooi8ee").to_bencode).to eq "d3:fooi8ee".to_slice
    end
  end
end
