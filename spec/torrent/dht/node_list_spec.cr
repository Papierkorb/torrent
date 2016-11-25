require "../../spec_helper"

Spec2.describe Torrent::Dht::NodeList do
  let(:node_id){ 10_000 }
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
end
