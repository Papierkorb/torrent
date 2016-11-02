require "../../spec_helper"

describe Torrent::Util::Endian do
  it "works with UInt8" do
    Torrent::Util::Endian.swap(0x11u8).should eq 0x11u8
  end

  it "works with UInt16" do
    Torrent::Util::Endian.swap(0x1122u16).should eq 0x2211u16
  end

  it "works with UInt32" do
    Torrent::Util::Endian.swap(0x11223344u32).should eq 0x44332211u32
  end

  it "works with UInt64" do
    Torrent::Util::Endian.swap(0x1122334455667788u64).should eq 0x8877665544332211u64
  end

  it "works with Int8" do
    Torrent::Util::Endian.swap(0x11i8).should eq 0x11i8
  end

  it "works with Int16" do
    Torrent::Util::Endian.swap(0x1122i16).should eq 0x2211i16
  end

  it "works with Int32" do
    Torrent::Util::Endian.swap(0x11223344i32).should eq 0x44332211i32
  end

  it "works with Int64" do
    Torrent::Util::Endian.swap(0x1122334455667788i64).should eq (0x8877665544332211u64).to_i64
  end
end
