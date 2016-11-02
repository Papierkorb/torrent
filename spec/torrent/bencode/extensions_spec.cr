require "../../spec_helper"

describe "Type.new extensions" do
  {% for type in %i[ UInt8 UInt16 UInt32 UInt64 Int8 Int16 Int32 Int64 ] %}
    it "works with {{ type }}" do
      {{ type.id }}.from_bencode("i5e".to_slice).should eq(5)
    end
  {% end %}

  it "works with String" do
    String.from_bencode("5:hello".to_slice).should eq "hello"
  end

  it "works with simple Array" do
    Array(Int32).from_bencode("li3ei4ei5ee".to_slice).should eq [ 3, 4, 5 ]
  end

  it "works with simple Hash" do
    Hash(String, Int32).from_bencode("d1:ai7e1:bi8ee".to_slice).should eq({ "a" => 7, "b" => 8 })
  end
end
