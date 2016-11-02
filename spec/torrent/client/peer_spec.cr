require "../../spec_helper"

private class TestHandler < Torrent::Extension::Handler
  getter peer : Torrent::Client::Peer?
  getter payload : Bytes?

  def invoke(peer : Torrent::Client::Peer, payload : Bytes)
    @peer = peer
    @payload = payload
  end
end

Spec2.describe Torrent::Client::Peer do
  let(:file){ Torrent::File.read("#{__DIR__}/../../fixtures/debian.torrent") }
  let(:file_manager){ Torrent::FileManager::FileSystem.new("/tmp") }
  let(:manager){ Torrent::Manager::Transfer.new(file, file_manager) }

  let(:empty){ Bytes.new(0) }

  let!(:set_spy){ Cute.spy subject, status_bit_set(bit : Torrent::Client::Peer::Status) }
  let!(:cleared_spy){ Cute.spy subject, status_bit_cleared(bit : Torrent::Client::Peer::Status) }

  subject{ TestPeer.new(manager.transfer) }

  before do
    subject.extension_map["foo"] = 5u8
    subject.extension_map["bar"] = 6u8
  end

  describe "#choke_peer" do
    it "sends a Choke packet" do
      subject.choke_peer
      expect(subject.packets.size).to eq 1

      packet = subject.packets.first
      expect(packet.type).to eq 0u8
      expect(packet.payload.empty?).to be_true

      expect(set_spy).to eq([ Torrent::Client::Peer::Status::ChokingPeer ])
    end
  end

  describe "#unchoke_peer" do
    it "sends an Unchoke packet" do
      subject.unchoke_peer
      expect(subject.packets.size).to eq 1

      packet = subject.packets.first
      expect(packet.type).to eq 1u8
      expect(packet.payload.empty?).to be_true

      expect(cleared_spy).to eq([ Torrent::Client::Peer::Status::ChokingPeer ])
    end
  end

  describe "#express_interest" do
    it "sends an Interested packet" do
      subject.express_interest
      expect(subject.packets.size).to eq 1

      packet = subject.packets.first
      expect(packet.type).to eq 2u8
      expect(packet.payload.empty?).to be_true

      expect(set_spy).to eq([ Torrent::Client::Peer::Status::InterestedInPeer ])
    end
  end

  describe "#express_no_interest" do
    it "sends an NotInterested packet" do
      subject.express_no_interest
      expect(subject.packets.size).to eq 1

      packet = subject.packets.first
      expect(packet.type).to eq 3u8
      expect(packet.payload.empty?).to be_true

      expect(cleared_spy).to eq([ Torrent::Client::Peer::Status::InterestedInPeer ])
    end
  end

  describe "#send_ping" do
    it "sends a Ping packet" do
      subject.send_ping
      expect(subject.packets.size).to eq 1

      packet = subject.packets.first
      expect(packet.ping?).to be_true
      expect(packet.payload.empty?).to be_true
    end
  end

  describe "#send_have" do
    it "sends a Have packet" do
      subject.send_have 0x11223344u32
      expect(subject.packets.size).to eq 1

      packet = subject.packets.first
      expect(packet.type).to eq 4u8
      expect(packet.payload.size).to eq 4
      expect(packet.payload).to eq Slice[ 0x11u8, 0x22u8, 0x33u8, 0x44u8 ]
    end
  end

  describe "#send_bitfield" do
    it "sends a Bitfield packet" do
      bits = Bytes.new(123, &.to_u8)
      subject.send_bitfield bits

      expect(subject.packets.size).to eq 1

      packet = subject.packets.first
      expect(packet.type).to eq 5u8
      expect(packet.payload).to eq bits
    end
  end

  describe "#send_request" do
    it "sends a Request packet" do
      subject.send_request 1u32, 2u32, 3u32
      expect(subject.packets.size).to eq 1

      packet = subject.packets.first
      expect(packet.type).to eq 6u8
      expect(packet.payload.size).to eq 12
      expect(packet.payload).to eq Slice[
        0u8, 0u8, 0u8, 1u8,
        0u8, 0u8, 0u8, 2u8,
        0u8, 0u8, 0u8, 3u8,
      ]
    end
  end

  describe "#send_cancel" do
    it "sends a Cancel packet" do
      subject.send_cancel 1u32, 2u32, 3u32
      expect(subject.packets.size).to eq 1

      packet = subject.packets.first
      expect(packet.type).to eq 8u8
      expect(packet.payload.size).to eq 12
      expect(packet.payload).to eq Slice[
        0u8, 0u8, 0u8, 1u8,
        0u8, 0u8, 0u8, 2u8,
        0u8, 0u8, 0u8, 3u8,
      ]
    end
  end

  context "with fast extension support" do
    before{ subject.fast_extension = true }

    describe "#send_bitfield(Util::Bitfield)" do
      context "given an all ones bitfield" do
        it "sends a HaveAll packet" do
          bits = Torrent::Util::Bitfield.new(Slice[ 0xFFu8 ])
          subject.send_bitfield bits
          expect(subject.packets.size).to eq 1

          packet = subject.packets.first
          expect(packet.type).to eq 0x0Eu8
          expect(packet.payload.size).to eq 0
        end
      end

      context "given an all zero bitfield" do
        it "sends a HaveNone packet" do
          bits = Torrent::Util::Bitfield.new(Slice[ 0x00u8 ])
          subject.send_bitfield bits
          expect(subject.packets.size).to eq 1

          packet = subject.packets.first
          expect(packet.type).to eq 0x0Fu8
          expect(packet.payload.size).to eq 0
        end
      end

      context "given a mixed bitfield" do
        it "sends a Bitfield packet" do
          bits = Torrent::Util::Bitfield.new(Slice[ 0x01u8 ])
          subject.send_bitfield bits

          expect(subject.packets.size).to eq 1

          packet = subject.packets.first
          expect(packet.type).to eq 5u8
          expect(packet.payload).to eq bits.data
        end
      end
    end

    describe "#send_have_all" do
      it "sends a HaveAll packet" do
        subject.send_have_all
        expect(subject.packets.size).to eq 1

        packet = subject.packets.first
        expect(packet.type).to eq 0x0Eu8
        expect(packet.payload.size).to eq 0
      end
    end

    describe "#send_have_none" do
      it "sends a HaveNone packet" do
        subject.send_have_none
        expect(subject.packets.size).to eq 1

        packet = subject.packets.first
        expect(packet.type).to eq 0x0Fu8
        expect(packet.payload.size).to eq 0
      end
    end

    describe "#suggest_piece" do
      it "sends a SuggestPiece packet" do
        subject.suggest_piece 0x11223344u32
        expect(subject.packets.size).to eq 1

        packet = subject.packets.first
        expect(packet.type).to eq 0x0Du8
        expect(packet.payload.size).to eq 4
        expect(packet.payload).to eq Slice[ 0x11u8, 0x22u8, 0x33u8, 0x44u8 ]
      end
    end

    describe "#reject_request" do
      it "sends a RejectRequest packet" do
        subject.reject_request 1u32, 2u32, 3u32
        expect(subject.packets.size).to eq 1

        packet = subject.packets.first
        expect(packet.type).to eq 0x10u8
        expect(packet.payload.size).to eq 12
        expect(packet.payload).to eq Slice[
          0u8, 0u8, 0u8, 1u8,
          0u8, 0u8, 0u8, 2u8,
          0u8, 0u8, 0u8, 3u8,
        ]
      end
    end

    describe "#send_allowed_fast_list" do
      it "sends a RejectRequest packet" do
        subject.send_allowed_fast_list [ 1u32, 2u32, 3u32 ]
        expect(subject.packets.size).to eq 1

        packet = subject.packets.first
        expect(packet.type).to eq 0x11u8
        expect(packet.payload.size).to eq 12
        expect(packet.payload).to eq Slice[
          0u8, 0u8, 0u8, 1u8,
          0u8, 0u8, 0u8, 2u8,
          0u8, 0u8, 0u8, 3u8,
        ]
      end
    end
  end

  context "with NO fast extension support" do
    before{ subject.fast_extension = false }

    describe "#send_bitfield(Util::Bitfield)" do
      context "given an all ones bitfield" do
        it "sends a Bitfield packet" do
          bits = Torrent::Util::Bitfield.new(Slice[ 0xFFu8 ])
          subject.send_bitfield bits

          expect(subject.packets.size).to eq 1
          packet = subject.packets.first
          expect(packet.type).to eq 5u8
          expect(packet.payload).to eq bits.data
        end
      end

      context "given an all zero bitfield" do
        it "sends a Bitfield packet" do
          bits = Torrent::Util::Bitfield.new(Slice[ 0x00u8 ])
          subject.send_bitfield bits

          expect(subject.packets.size).to eq 1
          packet = subject.packets.first
          expect(packet.type).to eq 5u8
          expect(packet.payload).to eq bits.data
        end
      end

      context "given a mixed bitfield" do
        it "sends a Bitfield packet" do
          bits = Torrent::Util::Bitfield.new(Slice[ 0x10u8 ])
          subject.send_bitfield bits

          expect(subject.packets.size).to eq 1
          packet = subject.packets.first
          expect(packet.type).to eq 5u8
          expect(packet.payload).to eq bits.data
        end
      end
    end

    describe "#send_have_all" do
      it "raises an error" do
        expect{ subject.send_have_all }.to raise_error(Torrent::Client::Error, match(/fast/i))
      end
    end

    describe "#send_have_none" do
      it "raises an error" do
        expect{ subject.send_have_none }.to raise_error(Torrent::Client::Error, match(/fast/i))
      end
    end

    describe "#suggest_piece" do
      it "raises an error" do
        expect{ subject.suggest_piece 123u32 }.to raise_error(Torrent::Client::Error, match(/fast/i))
      end
    end

    describe "#reject_request" do
      it "raises an error" do
        expect{ subject.reject_request 1u32, 2u32, 3u32 }.to raise_error(Torrent::Client::Error, match(/fast/i))
      end
    end

    describe "#send_allowed_fast_list" do
      it "raises an error" do
        expect{ subject.send_allowed_fast_list [ 1u32 ] }.to raise_error(Torrent::Client::Error, match(/fast/i))
      end
    end
  end

  context "with extended protocol support" do
    before{ subject.extension_protocol = true }

    describe "#send_extended(&block)" do
      it "yields if the extension is unknown" do
        yielded = false
        subject.send_extended("unknown"){ yielded = true }
        expect(yielded).to be_true
      end

      it "sends the packet" do
        yielded = false
        payload = Slice[ 5u8, 1u8, 2u8, 3u8, 4u8 ]
        subject.send_extended("foo", payload + 1){ yielded = true }

        expect(yielded).to be_false
        packet = subject.packets.first
        expect(packet.type).to eq 20u8
        expect(packet.payload.size).to eq payload.size
        expect(packet.payload).to eq payload
      end
    end

    describe "#send_extended(String)" do
      it "raises if the extension is unknown" do
        expect{ subject.send_extended("unknown") }.to raise_error(Torrent::Client::Error, match(/does not support the "unknown" extension/i))
      end

      it "sends the packet" do
        payload = Slice[ 6u8, 1u8, 2u8, 3u8, 4u8 ]
        subject.send_extended("bar", payload + 1)

        packet = subject.packets.first
        expect(packet.type).to eq 20u8
        expect(packet.payload.size).to eq payload.size
        expect(packet.payload).to eq payload
      end
    end

    describe "#send_extended(UInt8)" do
      it "sends the packet" do
        payload = Slice[ 100u8, 1u8, 2u8, 3u8, 4u8 ]
        subject.send_extended(100u8, payload + 1)

        packet = subject.packets.first
        expect(packet.type).to eq 20u8
        expect(packet.payload.size).to eq payload.size
        expect(packet.payload).to eq payload
      end
    end

    describe "#send_extended?" do
      it "returns false if the extension is unknown" do
        expect(subject.send_extended?("unknown")).to be_false
      end

      it "sends the packet and returns true" do
        payload = Slice[ 6u8, 1u8, 2u8, 3u8, 4u8 ]
        expect(subject.send_extended?("bar", payload + 1)).to be_true

        packet = subject.packets.first
        expect(packet.type).to eq 20u8
        expect(packet.payload.size).to eq payload.size
        expect(packet.payload).to eq payload
      end
    end
  end

  context "with NO extended protocol support" do
    before{ subject.extension_protocol = false }

    describe "#send_extended(&block)" do
      it "yields" do
        yielded = false
        subject.send_extended("foo"){ yielded = true }
        expect(yielded).to be_true
      end
    end

    describe "#send_extended(String)" do
      it "raises an Error" do
        expect{ subject.send_extended("foo") }.to raise_error(Torrent::Client::Error, match(/does not support extensions/i))
      end
    end

    describe "#send_extended(UInt8)" do
      it "raises an Error" do
        expect{ subject.send_extended(4u8) }.to raise_error(Torrent::Client::Error, match(/does not support extensions/i))
      end
    end

    describe "#send_extended?" do
      it "returns false" do
        expect(subject.send_extended?("foo")).to be_false
      end
    end
  end

  describe "#handle_packet" do
    context "choke" do
      it "sets the choked by peer flag" do
        subject.handle_packet(0u8, empty)

        expect(subject.status.choked_by_peer?).to be_true
        expect(set_spy).to eq [ Torrent::Client::Peer::Status::ChokedByPeer ]
      end
    end

    context "unchoke" do
      it "clears the choked by peer flag" do
        subject.handle_packet(1u8, empty)

        expect(subject.status.choked_by_peer?).to be_false
        expect(cleared_spy).to eq [ Torrent::Client::Peer::Status::ChokedByPeer ]
      end
    end

    context "interested" do
      it "clears the peer is interested flag" do
        subject.handle_packet(2u8, empty)

        expect(subject.status.peer_is_interested?).to be_true
        expect(set_spy).to eq [ Torrent::Client::Peer::Status::PeerIsInterested ]
      end
    end

    context "not interested" do
      it "clears the peer is interested flag" do
        subject.handle_packet(3u8, empty)

        expect(subject.status.peer_is_interested?).to be_false
        expect(cleared_spy).to eq [ Torrent::Client::Peer::Status::PeerIsInterested ]
      end
    end

    context "have" do
      it "sets the corresponding bit in the bitfield" do
        spy = Cute.spy subject, have_received(piece_index : UInt32)
        subject.bitfield = Torrent::Util::Bitfield.new(16)
        subject.handle_packet(4u8, Slice[ 0u8, 0u8, 0u8, 3u8 ])

        expect(subject.bitfield.data).to eq Slice[ 0x10u8, 0u8 ]
        expect(spy).to eq [ 3u32 ]
      end
    end

    context "bitfield" do
      it "sets the bitfield" do
        bits = Torrent::Util::Bitfield.new(file.piece_count)
        subject.handle_packet(5u8, bits.data)

        expect(subject.bitfield.data).to eq bits.data
      end

      it "raises if the bitfield has wrong byte size" do
        bits = Torrent::Util::Bitfield.new(file.piece_count - 8)

        expect{ subject.handle_packet(5u8, bits.data) }.to raise_error(Torrent::Client::Error, match(/sent bitfield packet/i))

        expect(subject.bitfield.data).to eq empty
      end
    end

    context "extended" do
      it "invokes the extension handler" do
        handler = TestHandler.new("Test", manager)
        id = manager.extensions.add handler

        payload = Slice[ id, 88u8, 89u8 ]
        subject.handle_packet(20u8, payload)

        expect(handler.peer).not_to be_nil
        expect(handler.peer).to be subject
        expect(handler.payload).to eq(payload + 1)
      end
    end

    context "have all" do
      it "initializes the bitfield to all-ones" do
        bits = Torrent::Util::Bitfield.new(file.piece_count, 0xFFu8)
        subject.handle_packet(0x0Eu8, empty)

        expect(subject.bitfield.data).to eq bits.data
      end
    end

    context "have none" do
      it "initializes the bitfield to all-zero" do
        bits = Torrent::Util::Bitfield.new(file.piece_count, 0u8)
        subject.handle_packet(0x0Fu8, empty)

        expect(subject.bitfield.data).to eq bits.data
      end
    end

    context "suggest piece" do
      it "emits piece_suggested" do
        spy = Cute.spy subject, piece_suggested(piece_index : UInt32)
        subject.handle_packet(0x0Du8, Slice[ 0x11u8, 0x22u8, 0x33u8, 0x44u8 ])

        expect(spy).to eq [ 0x11223344u32 ]
      end
    end

    context "reject request" do
      it "emits request_rejected" do
        spy = Cute.spy subject, request_rejected(rejection : Torrent::Client::Protocol::RejectRequest)
        subject.handle_packet(0x10u8, Slice[
          0u8, 0u8, 0u8, 1u8,
          0u8, 0u8, 0u8, 2u8,
          0u8, 0u8, 0u8, 3u8,
        ])

        expect(spy.size).to eq 1
        reject = spy.first
        expect(reject.index).to eq 1
        expect(reject.start).to eq 2
        expect(reject.length).to eq 3
      end
    end

    context "allowed fast" do
      it "emits fast_list_received" do
        spy = Cute.spy subject, fast_list_received(list : Array(UInt32))
        subject.handle_packet(0x11u8, Slice[
          0u8, 0u8, 0u8, 1u8,
          0u8, 0u8, 0u8, 2u8,
          0u8, 0u8, 0u8, 3u8,
        ])

        expect(spy).to eq [ [ 1u32, 2u32, 3u32 ] ]
      end
    end
  end
end
