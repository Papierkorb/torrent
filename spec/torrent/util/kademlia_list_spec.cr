require "../../spec_helper"

private class KademliaObject
  @hash : BigInt

  def initialize(hash : Int)
    @hash = hash.to_big_i
  end

  def kademlia_distance(other : Int) : BigInt
    @hash ^ other.to_big_i
  end
end

Spec2.describe Torrent::Util::KademliaList do
  let(:a){ KademliaObject.new 1 }
  let(:b){ KademliaObject.new 2 }
  let(:c){ KademliaObject.new 3 }
  let(:d){ KademliaObject.new 4 }
  let(:e){ KademliaObject.new 5 }
  let(:f){ KademliaObject.new 6 }
  let(:g){ KademliaObject.new 7 }
  let(:h){ KademliaObject.new 8 }
  let(:i){ KademliaObject.new 12 }

  let(:compare){ 3.to_big_i }
  let(:max_size){ 4 }

  subject do
    Torrent::Util::KademliaList(KademliaObject).new(compare, max_size).tap do |list|
      list << a << b << c << d << e << f << g << h
    end
  end

  describe "#to_a" do
    it "returns the element array" do
      expect(subject.to_a).to eq [ c, b, a, g ]
    end
  end

  describe "#try_add" do
    context "if the element is already in the list" do
      it "returns false" do
        expect(subject.try_add b).to be_false
        expect(subject.to_a).to eq [ c, b, a, g ]
      end
    end
  end

  describe "#<<" do
    before do
      subject.clear
      subject << b << f << d
    end

    context "if the added object is farther than the farthest" do
      context "and the list is full" do
        it "does nothing" do
          subject << h << i
          expect(subject.to_a).to eq [ b, f, d, h ]
        end
      end

      it "adds the element at the end" do
        subject << i
        expect(subject.to_a).to eq [ b, f, d, i ]
      end
    end

    context "if the added object is nearer than the nearest" do
      it "adds the element at the start" do
        subject << c
        expect(subject.to_a).to eq [ c, b, f, d ]
      end
    end

    it "adds the element in the middle" do
      subject << e
      expect(subject.to_a).to eq [ b, f, e, d ]
    end
  end
end
