require "../../spec_helper"

private def any(code)
  Torrent::Bencode.load(code.to_slice)
end

describe Torrent::Bencode::Any do
  context "#object" do
    it "returns the integer on an integer" do
      any("i5e").object.should eq 5i64
    end

    it "returns the slice on a byte string" do
      any("4:okay").object.should eq "okay".to_slice
    end

    it "returns the array on an array" do
      any("li3ee").object.should eq([ any("i3e") ])
    end

    it "returns the hash on a hash" do
      any("d3:fooi8ee").object.should eq({ "foo" => any("i8e") })
    end
  end

  context "#to_i" do
    it "returns the integer on an integer" do
      any("i5e").to_i.should eq 5i64
    end

    it "fails on a byte string" do
      expect_raises(Torrent::Bencode::Any::Error){ any("4:okay").to_i }
    end

    it "fails on an array" do
      expect_raises(Torrent::Bencode::Any::Error){ any("li3ee").to_i }
    end

    it "fails on a hash" do
      expect_raises(Torrent::Bencode::Any::Error){ any("d3:fooi8ee").to_i }
    end
  end

  context "#to_s" do
    it "returns the integer on an integer" do
      any("i5e").to_s.should eq 5i64.to_s
    end

    it "returns the string on a byte string" do
      any("4:okay").to_s.should eq "okay".to_s
    end

    it "returns the array on an array" do
      any("li3ee").to_s.should eq([ any("i3e") ].to_s)
    end

    it "returns the hash on a hash" do
      any("d3:fooi8ee").to_s.should eq({ "foo" => any("i8e") }.to_s)
    end
  end

  context "#to_a" do
    it "fails on an integer" do
      expect_raises(Torrent::Bencode::Any::Error){ any("i5e").to_a }
    end

    it "fails on a byte string" do
      expect_raises(Torrent::Bencode::Any::Error){ any("4:okay").to_a }
    end

    it "returns the array on an array" do
      any("li3ee").to_a.should eq [ any("i3e") ]
    end

    it "fails on a hash" do
      expect_raises(Torrent::Bencode::Any::Error){ any("d3:fooi8ee").to_a }
    end
  end

  context "#to_h" do
    it "fails on an integer" do
      expect_raises(Torrent::Bencode::Any::Error){ any("i5e").to_h }
    end

    it "fails on a byte string" do
      expect_raises(Torrent::Bencode::Any::Error){ any("4:okay").to_h }
    end

    it "fails on an array" do
      expect_raises(Torrent::Bencode::Any::Error){ any("li3ee").to_h }
    end

    it "returns the hash on a hash" do
      any("d3:fooi8ee").to_h.should eq({ "foo" => any("i8e") })
    end
  end

  context "#to_b" do
    it "returns true for a non-zero integer" do
      any("i1e").to_b.should be_true
    end

    it "returns false for a non-zero integer" do
      any("i0e").to_b.should be_false
    end

    it "fails for anything but an integer" do
      expect_raises(Torrent::Bencode::Any::Error){ any("4:okay").to_b }
      expect_raises(Torrent::Bencode::Any::Error){ any("li3ee").to_b }
      expect_raises(Torrent::Bencode::Any::Error){ any("d3:fooi8ee").to_b }
    end
  end

  context "#size" do
    it "fails on an integer" do
      expect_raises(Torrent::Bencode::Any::Error){ any("i5e").size }
    end

    it "returns the size on a byte string" do
      any("4:okay").size.should eq 4
    end

    it "returns the size on an array" do
      any("li3ee").size.should eq 1
    end

    it "returns the size on a hash" do
      any("d3:fooi8ee").size.should eq 1
    end
  end

  context "#[]" do
    it "fails on an integer" do
      expect_raises(Torrent::Bencode::Any::Error){ any("i5e")[0] }
    end

    it "fails on a byte string" do
      expect_raises(Torrent::Bencode::Any::Error){ any("3:foo")[0] }
    end

    it "works on an array in-bounds" do
      any("li3ee")[0].should eq any("i3e")
    end

    it "works on a hash if the key is found" do
      any("d3:fooi8ee")["foo"].should eq any("i8e")
    end

    it "fails on an array out-of-bounds" do
      expect_raises(IndexError){ any("li3ee")[1] }
    end

    it "fails on a hash if the key is NOT found" do
      expect_raises(KeyError){ any("d3:fooi8ee")["bar"] }
    end
  end

  context "#[]?" do
    it "fails on an integer" do
      expect_raises(Torrent::Bencode::Any::Error){ any("i5e")[0]? }
    end

    it "fails on a byte string" do
      expect_raises(Torrent::Bencode::Any::Error){ any("3:foo")[0]? }
    end

    it "works on an array in-bounds" do
      any("li3ee")[0]?.should eq any("i3e")
    end

    it "works on a hash if the key is found" do
      any("d3:fooi8ee")["foo"]?.should eq any("i8e")
    end

    it "returns nil on an array out-of-bounds" do
      any("li3ee")[1]?.should be_nil
    end

    it "returns nil on a hash if the key is NOT found" do
      any("d3:fooi8ee")["bar"]?.should be_nil
    end
  end

  context "#to_bencode" do
    it "returns the bencode data for an integer" do
      any("i5e").to_bencode.should eq "i5e".to_slice
    end

    it "returns the bencode data for a byte string" do
      any("4:okay").to_bencode.should eq "4:okay".to_slice
    end

    it "returns the bencode data for an array" do
      any("li3ee").to_bencode.should eq "li3ee".to_slice
    end

    it "returns the bencode data for a hash" do
      any("d3:fooi8ee").to_bencode.should eq "d3:fooi8ee".to_slice
    end
  end
end
