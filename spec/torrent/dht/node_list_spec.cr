require "../../spec_helper"

Spec2.describe Torrent::Dht::NodeList do
  let(:node_id){ 10_000.to_big_i }
  subject{ described_class.new node_id }

  describe "#initialize" do
    context "if the node_id is less than 0" do
      let(:node_id){ -1 }
      it "raises" do
        expect{ subject }.to raise_error(ArgumentError, match /out of range/i)
      end
    end

    context "if the node_id equals 2**160" do
      let(:node_id){ BigInt.new(2)**160 }
      it "raises" do
        expect{ subject }.to raise_error(ArgumentError, match /out of range/i)
      end
    end

    context "if the node_id is greater than 2**160" do
      let(:node_id){ BigInt.new(2)**160 + 1 }
      it "raises" do
        expect{ subject }.to raise_error(ArgumentError, match /out of range/i)
      end
    end

    context "if the node_id is in range" do
      it "does not raise" do
        expect{ subject }.not_to raise_error
      end
    end
  end

  describe "#find_bucket" do
    context "if the id is less than 0" do
      it "raises an IndexError" do
        expect{ subject.find_bucket(-1.to_big_i) }.to raise_error IndexError
      end
    end

    context "if the id is 2**160 or greater" do
      it "raises an IndexError" do
        expect{ subject.find_bucket(2.to_big_i ** 160) }.to raise_error IndexError
        expect{ subject.find_bucket(2.to_big_i ** 160 + 1) }.to raise_error IndexError
      end
    end

    it "returns the bucket responsible for the id" do
      expect(subject.find_bucket(1234.to_big_i)).to be_a(Torrent::Dht::Bucket)
    end
  end

  describe "#would_accept?" do
    it "rejects ourself" do
      expect(subject.would_accept? node_id).to be_false
    end

    it "rejects known nodes" do
      expect(subject.try_add node(100)).to be_true
      expect(subject.would_accept? node(100).id).to be_false
    end

    context "if bucket is full" do
      before do
        8.times{|i| subject.try_add node(node_id + i)}
      end

      it "rejects if bucket is not splittable" do
        expect(subject.would_accept?(node_id - 1)).to be_false
      end

      it "accepts if bucket is splittable" do
        expect(subject.would_accept?(2.to_big_i ** 160 - 200)).to be_true
      end
    end

    it "accepts otherwise" do
      expect(subject.would_accept? node(100).id).to be_true
    end
  end

  describe "#try_add" do
    it "rejects ourself" do
      expect(subject.try_add node(node_id - 100)).to be_false
    end

    it "rejects known nodes" do
      expect(subject.try_add node(100)).to be_true
      expect(subject.try_add node(100)).to be_false
    end

    context "if bucket is full" do
      before do
        8.times{|i| subject.try_add node(node_id + i)}
      end

      it "rejects if bucket is not splittable" do
        expect(subject.try_add node(node_id - 1)).to be_false
      end

      it "accepts if bucket is splittable" do
        expect(subject.try_add node(2.to_big_i ** 160 - 200)).to be_true
      end
    end

    it "accepts otherwise" do
      expect(subject.try_add node(100)).to be_true
    end
  end
end
