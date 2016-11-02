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

describe "Torrent::Bencode.mapping" do
  context ".from_bencode" do
    it "works in the general case" do
      test = Test.from_bencode("d3:fooi7e4:manyle3:numi-1ee".to_slice)
      test.foo.should eq 7
      test.opt.should be_nil
      test.num.should eq -1
      test.many.empty?.should be_true
    end

    it "uses default values" do
      test = Test.from_bencode("d3:fooi7e4:manylee".to_slice)
      test.foo.should eq 7
      test.opt.should be_nil
      test.num.should eq 4
      test.many.empty?.should be_true
    end

    it "works with custom key" do
      test = Test.from_bencode("d3:fooi7e4:manyle3:bar3:^_^e".to_slice)
      test.foo.should eq 7
      test.opt.should eq "^_^"
      test.num.should eq 4
      test.many.empty?.should be_true
    end

    it "can build recursive structures" do
      test = Test.from_bencode("d3:fooi7e4:manyld3:fooi7e4:manyle3:numi-1eeee".to_slice)
      test.foo.should eq 7
      test.opt.should be_nil
      test.num.should eq 4
      test.many.size.should eq 1

      inner = test.many.first
      inner.foo.should eq 7
      inner.opt.should be_nil
      inner.num.should eq -1
      inner.many.empty?.should be_true
    end

    it "fails if an attribute is missing" do
      expect_raises(Torrent::Bencode::Error, /missing/i) do
        Test.from_bencode("d4:manylee".to_slice)
      end
    end

    it "ignores unknown attributes" do
      test = Test.from_bencode("d7:unknownd3:fooi9ee3:fooi7e4:manylee".to_slice)
      test.foo.should eq 7
      test.opt.should be_nil
      test.num.should eq 4
      test.many.empty?.should be_true
    end

    it "supports a converter" do
      test = ConverterTest.from_bencode("d3:fooi7e3:bari4ee".to_slice)
      test.foo.should eq 14
      test.bar.should eq 8
    end

    it "supports a converter with default value" do
      test = ConverterTest.from_bencode("d3:fooi7ee".to_slice)
      test.foo.should eq 14
      test.bar.should eq 5
    end
  end

  context ".from_bencode strict mode" do
    it "works with no unknown attributes" do
      test = StrictTest.from_bencode("d3:fooi7ee".to_slice)
      test.foo.should eq 7
    end

    it "fails if an attribute is unknown" do
      expect_raises(Torrent::Bencode::Error, /unknown attribute/i) do
        StrictTest.from_bencode("d3:fooi7e3:bar3:asde".to_slice)
      end
    end
  end

  context "#to_bencode" do
    it "sorts the dictionary keys" do
      test = Test.from_bencode("d4:manyld3:fooi7e4:manyle3:numi-1eee3:fooi7ee".to_slice)
      test.to_bencode.should eq "d3:fooi7e4:manyld3:fooi7e4:manyle3:numi-1eee3:numi4ee".to_slice
    end

    it "supports a converter" do
      test = ConverterTest.new(foo: 2, bar: 3)
      test.to_bencode.should eq "d3:bari6e3:fooi4ee".to_slice
    end

    it "uses the custom key" do
      test = Test.new(foo: 5, opt: "Ok", num: 4, many: [ ] of Test)
      test.to_bencode.should eq "d3:bar2:Ok3:fooi5e4:manyle3:numi4ee".to_slice
    end
  end
end
