require "../../spec_helper"

Spec2.describe Torrent::Util::RequestList::Piece do
  let(:index){ 1234u32 }
  let(:size){ 160u32 }
  let(:block_size){ 16u32 }

  subject{ described_class.new(index, size, block_size) }

  describe "#count" do
    context "if the piece size is multiple of block size" do
      it "equals size / block_size" do
        expect(subject.count).to eq 10
      end
    end

    context "if the piece size is not multiple of block size" do
      let(:size){ 165u32 }

      it "equals size / block_size + 1" do
        expect(subject.count).to eq 11
      end
    end
  end

  describe "#complete?" do
    context "if @progress is not all true" do
      it "returns false" do
        subject.progress.map!{ true }
        subject.progress[0] = false
        expect(subject.complete?).to be_false
      end
    end

    context "if @progress is all true" do
      it "returns true" do
        subject.progress.map!{ true }
        expect(subject.complete?).to be_true
      end
    end
  end

  describe "#complete?(block_idx)" do
    context "if the block is complete" do
      it "returns true" do
        subject.progress[1] = true
        expect(subject.complete? 1).to be_true
      end
    end

    context "if the block is not complete" do
      it "returns true" do
        subject.progress[1] = false
        expect(subject.complete? 1).to be_false
      end
    end
  end

  describe "#offset_to_block" do
    context "if the offset is not divisible by the block size" do
      it "raises an ArgumentError" do
        expect{ subject.offset_to_block 5 }.to raise_error(ArgumentError, match /not divisible by block size/i)
      end
    end

    it "returns the block index" do
      expect(subject.offset_to_block 0).to eq 0
      expect(subject.offset_to_block 16).to eq 1
      expect(subject.offset_to_block 32).to eq 2
    end
  end

  describe "#mark_complete" do
    context "if now all blocks are complete" do
      it "returns true" do
        subject.progress.map!{ true }
        subject.progress[1] = false

        expect(subject.mark_complete 1).to be_true
        expect(subject.complete?).to be_true
      end
    end

    context "if not all blocks are complete" do
      it "returns false" do
        subject.progress.map!{ true }
        subject.progress[1] = false
        subject.progress[2] = false

        expect(subject.mark_complete 1).to be_false
        expect(subject.complete?).to be_false
      end
    end
  end

  describe "#to_a" do
    let(:size){ 38u32 }

    it "returns an array of all tuples" do
      expect(subject.to_a).to eq([
        { 1234u32, 0u32, 16u32 },
        { 1234u32, 16u32, 16u32 },
        { 1234u32, 32u32, 6u32 },
      ])
    end
  end

  describe "#tuple" do
    context "if the last block is divisible by the block size" do
      it "returns a tuple" do
        expect(subject.tuple 9).to eq({ 1234u32, 9 * 16u32, 16u32 })
      end
    end

    context "if the last block is not divisible by the block size" do
      let(:size){ 155u32 }

      it "returns a tuple" do
        expect(subject.tuple 9).to eq({ 1234u32, 9 * 16u32, 11u32 })
      end
    end

    context "if the index is not the last block" do
      it "returns a tuple" do
        expect(subject.tuple 1).to eq({ 1234u32, 16u32, 16u32 })
      end
    end
  end
end
