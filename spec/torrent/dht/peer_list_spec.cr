require "../../spec_helper"

Spec2.describe Torrent::Dht::PeerList do
  subject{ described_class.new 1.to_big_i }

  before do
    subject.add "1.1.1.1", 1u16
    subject.add "2.2.2.2", 2u16
    subject.add "3.3.3.3", 3u16
    subject.add "4.4.4.4", 4u16
  end

  describe "#checkout_timeouts" do
    let(:old){ { Time.new(2016, 11, 17, 16, 0, 0), Bytes.new(1) } }
    let(:current){ { Time.now, Bytes.new(2) } }
    before do
      subject.peers.clear
      subject.peers << old << current
    end

    it "removes older peers" do
      subject.check_timeouts
      expect(subject.peers.size).to eq 1
      expect(subject.peers).to eq [ current ]
    end
  end

  describe "#add" do
    context "if the peer is already known" do
      it "updates the time" do
        before = subject.peers.first[0]
        subject.add "1.1.1.1", 1u16
        after = subject.peers.first[0]

        expect(subject.peers.size).to eq 4
        expect(after).not_to eq before
      end
    end

    context "if the peer list is full" do
      let(:fake){ { Time.now, Bytes.new(1) } }

      before do
        subject.peers.clear
        1000.times{ subject.peers << fake }
      end

      it "rejects the peer" do
        subject.add "1.2.3.4", 1234u16

        expect(subject.peers.size).to eq 1000
        expect(subject.peers.all?(&.==(fake))).to be_true
      end
    end

    it "adds the peer" do
      subject.add "5.5.5.5", 5u16

      expect(subject.peers.size).to eq 5
      time, native = subject.peers[4]
      expect(native).to eq Slice[ 5u8, 5u8, 5u8, 5u8, 0u8, 5u8 ]
      expect(time).to_be > Time.now - 1.second
    end
  end
end
