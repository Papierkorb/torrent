require "../../spec_helper"

Spec2.describe "Type.new extensions" do
  {% for type in %i[ UInt8 UInt16 UInt32 UInt64 Int8 Int16 Int32 Int64 ] %}
    it "works with {{ type }}" do
      expect({{ type.id }}.from_bencode("i5e".to_slice)).to eq(5)
    end
  {% end %}

  it "works with String" do
    expect(String.from_bencode("5:hello".to_slice)).to eq "hello"
  end

  it "works with simple Array" do
    expect(Array(Int32).from_bencode("li3ei4ei5ee".to_slice)).to eq [ 3, 4, 5 ]
  end

  it "works with simple Hash" do
    expect(Hash(String, Int32).from_bencode("d1:ai7e1:bi8ee".to_slice)).to eq({ "a" => 7, "b" => 8 })
  end
end
