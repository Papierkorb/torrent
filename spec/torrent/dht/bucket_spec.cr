require "../../spec_helper"

Spec2.describe Torrent::Dht::Bucket do
  let(:range){ 100.to_big_i...200.to_big_i }
  let(:nodes){ Array(Torrent::Dht::Node).new(Torrent::Dht::Bucket::MAX_NODES) }

  let(:node_a){ node 10 }
  let(:node_b){ node 20 }
  let(:node_outside){ node 10_000 }

  subject{ described_class.new range, nodes, Time.now }

  describe "#full?" do
    context "if less than 8 nodes are in it" do
      it "returns false" do
        7.times{|i| nodes << node i}
        expect(subject.full?).to be_false
      end
    end

    context "if 8 nodes are in it" do
      it "returns true" do
        8.times{|i| nodes << node i}
        expect(subject.full?).to be_true
      end
    end
  end

  describe "#includes?(Node)" do
    before{ nodes << node_a << node_b }

    context "if it knows the Node" do
      it "returns true" do
        expect(subject.includes? node_a).to be_true
      end
    end

    context "if it does NOT know the Node" do
      it "returns false" do
        expect(subject.includes? node_outside).to be_false
      end
    end
  end

  describe "#includes?(BigInt)" do
    before{ nodes << node_a << node_b }

    context "if it knows the node id" do
      it "returns true" do
        expect(subject.includes? node_a.id).to be_true
      end
    end

    context "if it does NOT know the node id" do
      it "returns false" do
        expect(subject.includes? node_outside.id).to be_false
      end
    end
  end

  describe "#find_node" do
    before{ nodes << node_a << node_b }

    context "if it knows the node id" do
      it "returns the node" do
        expect(subject.find_node node_a.id).to be node_a
        expect(subject.find_node node_b.id).to be node_b
      end
    end

    context "else" do
      it "returns nil" do
        expect(subject.find_node node_outside.id).to be_nil
      end
    end
  end

  describe "#splittable?" do
    context "if the buckets range is large enough" do
      it "returns true" do
        expect(subject.splittable?).to be_true
      end
    end

    context "if the bucket is pretty small already" do
      let(:range){ 1.to_big_i..8.to_big_i }
      it "returns false" do
        expect(subject.splittable?).to be_false
      end
    end
  end

  describe "#split" do
    it "returns two buckets containing the left and right portions" do
      8.times{|i| nodes << node 47 + i}

      left, right = subject.split
      expect(left.range).to eq 100.to_big_i...150.to_big_i
      expect(right.range).to eq 150.to_big_i...200.to_big_i

      expect(left.includes? nodes[0].not_nil!).to be_true
      expect(left.includes? nodes[1].not_nil!).to be_true
      expect(left.includes? nodes[2].not_nil!).to be_true
      expect(left.includes? nodes[3].not_nil!).to be_true
      expect(left.includes? nodes[4].not_nil!).to be_false
      expect(left.includes? nodes[5].not_nil!).to be_false
      expect(left.includes? nodes[6].not_nil!).to be_false
      expect(left.includes? nodes[7].not_nil!).to be_false

      expect(right.includes? nodes[0].not_nil!).to be_false
      expect(right.includes? nodes[1].not_nil!).to be_false
      expect(right.includes? nodes[2].not_nil!).to be_false
      expect(right.includes? nodes[3].not_nil!).to be_false
      expect(right.includes? nodes[4].not_nil!).to be_true
      expect(right.includes? nodes[5].not_nil!).to be_true
      expect(right.includes? nodes[6].not_nil!).to be_true
      expect(right.includes? nodes[7].not_nil!).to be_true

      expect(left.full?).to be_false
      expect(right.full?).to be_false
      expect(left.last_refresh).to eq subject.last_refresh
      expect(right.last_refresh).to eq subject.last_refresh
      expect(left.node_count).to eq 4
      expect(right.node_count).to eq 4
    end
  end

  describe "#add" do
    context "if the bucket is full" do
      it "raises an ArgumentError" do
        8.times{|i| nodes << node i }

        expect{ subject.add node_a }.to raise_error(ArgumentError, "Bucket is full")
      end
    end

    context "if the node id is out of range" do
      it "raises an IndexError" do
        expect{ subject.add node(1000) }.to raise_error(IndexError, match /range/i)
      end
    end

    context "if the node is already in the list" do
      it "does nothing" do
        nodes << node_a << node_b
        subject.add node_a
        expect(nodes).to eq [ node_a, node_b ]
      end
    end

    it "adds a node" do
      subject.add node_a
      expect(nodes).to eq [ node_a ]

      subject.add node_b
      expect(nodes).to eq [ node_a, node_b ]
    end
  end

  describe "#delete" do
    before{ nodes << node_a << node_b }

    it "removes a node" do
      subject.delete node_a
      expect(nodes).to eq [ node_b ]
    end
  end

  describe "#should_split?" do
    context "if the left side is full" do
      before do
        (0..7).each{|i| nodes << node(i) }
      end

      context "and the id is in the left" do
        it "returns false" do
          expect(subject.should_split? 110.to_big_i).to be_false
        end
      end

      context "and the id is in the right" do
        it "returns true" do
          expect(subject.should_split? 160.to_big_i).to be_true
        end
      end
    end

    context "if the right side is full" do
      before do
        (51..58).each{|i| nodes << node(i) }
      end

      context "and the id is in the left" do
        it "returns true" do
          expect(subject.should_split? 110.to_big_i).to be_true
        end
      end

      context "and the id is in the right" do
        it "returns false" do
          expect(subject.should_split? 160.to_big_i).to be_false
        end
      end
    end
  end
end
