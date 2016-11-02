require "../../spec_helper"

private class Test
  Torrent::Bencode.mapping(
    foo: Int32,
    opt: { nilable: true, type: String, key: :bar },
    num: { nilable: true, type: Int32, default: 4 },
    many: Array(Test),
  )

  def initialize(@foo, @opt, @num, @many)
  end
end

private class StrictTest
  Torrent::Bencode.mapping({ foo: Int32 }, strict: true)
end

private class DoubleConverter
  def self.from_bencode(pull)
    pull.read_integer.to_i32 * 2
  end

  def self.to_bencode(value, io)
    (value * 2).to_bencode io
  end
end

private class ConverterTest
  Torrent::Bencode.mapping(
    foo: { type: Int32, converter: DoubleConverter },
    bar: { type: Int32, converter: DoubleConverter, default: 5 },
  )

  def initialize(@foo, @bar)
  end
end

Spec2.describe "Torrent::Bencode.mapping" do
  describe ".from_bencode" do
    it "works in the general case" do
      test = Test.from_bencode("d3:fooi7e4:manyle3:numi-1ee".to_slice)
      expect(test.foo).to eq 7
      expect(test.opt).to be_nil
      expect(test.num).to eq -1
      expect(test.many.empty?).to be_true
    end

    it "uses default values" do
      test = Test.from_bencode("d3:fooi7e4:manylee".to_slice)
      expect(test.foo).to eq 7
      expect(test.opt).to be_nil
      expect(test.num).to eq 4
      expect(test.many.empty?).to be_true
    end

    it "works with custom key" do
      test = Test.from_bencode("d3:fooi7e4:manyle3:bar3:^_^e".to_slice)
      expect(test.foo).to eq 7
      expect(test.opt).to eq "^_^"
      expect(test.num).to eq 4
      expect(test.many.empty?).to be_true
    end

    it "can build recursive structures" do
      test = Test.from_bencode("d3:fooi7e4:manyld3:fooi7e4:manyle3:numi-1eeee".to_slice)
      expect(test.foo).to eq 7
      expect(test.opt).to be_nil
      expect(test.num).to eq 4
      expect(test.many.size).to eq 1

      inner = test.many.first
      expect(inner.foo).to eq 7
      expect(inner.opt).to be_nil
      expect(inner.num).to eq -1
      expect(inner.many.empty?).to be_true
    end

    it "fails if an attribute is missing" do
      expect{ Test.from_bencode("d4:manylee".to_slice) }.to raise_error(Torrent::Bencode::Error, match /missing/i)
    end

    it "ignores unknown attributes" do
      test = Test.from_bencode("d7:unknownd3:fooi9ee3:fooi7e4:manylee".to_slice)
      expect(test.foo).to eq 7
      expect(test.opt).to be_nil
      expect(test.num).to eq 4
      expect(test.many.empty?).to be_true
    end

    it "supports a converter" do
      test = ConverterTest.from_bencode("d3:fooi7e3:bari4ee".to_slice)
      expect(test.foo).to eq 14
      expect(test.bar).to eq 8
    end

    it "supports a converter with default value" do
      test = ConverterTest.from_bencode("d3:fooi7ee".to_slice)
      expect(test.foo).to eq 14
      expect(test.bar).to eq 5
    end
  end

  describe ".from_bencode strict mode" do
    it "works with no unknown attributes" do
      test = StrictTest.from_bencode("d3:fooi7ee".to_slice)
      expect(test.foo).to eq 7
    end

    it "fails if an attribute is unknown" do
      expect{ StrictTest.from_bencode("d3:fooi7e3:bar3:asde".to_slice) }.to raise_error(Torrent::Bencode::Error, match /unknown attribute/i)
    end
  end

  describe "#to_bencode" do
    it "sorts the dictionary keys" do
      test = Test.from_bencode("d4:manyld3:fooi7e4:manyle3:numi-1eee3:fooi7ee".to_slice)
      expect(test.to_bencode).to eq "d3:fooi7e4:manyld3:fooi7e4:manyle3:numi-1eee3:numi4ee".to_slice
    end

    it "supports a converter" do
      test = ConverterTest.new(foo: 2, bar: 3)
      expect(test.to_bencode).to eq "d3:bari6e3:fooi4ee".to_slice
    end

    it "uses the custom key" do
      test = Test.new(foo: 5, opt: "Ok", num: 4, many: [ ] of Test)
      expect(test.to_bencode).to eq "d3:bar2:Ok3:fooi5e4:manyle3:numi4ee".to_slice
    end
  end
end
