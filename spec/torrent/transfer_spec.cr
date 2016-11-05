require "../spec_helper"

Mocks.create_mock Torrent::LeechStrategy::Default do
  mock start
end

Spec2.describe Torrent::Transfer do
  let(:file){ Torrent::File.read("#{__DIR__}/../fixtures/debian.torrent") }
  let(:file_manager){ Torrent::FileManager::FileSystem.new("/tmp") }
  let(:manager){ Torrent::Manager::Transfer.new(file, file_manager) }

  let(:downloaded){ 1000u64 }
  let(:uploaded){ 100u64 }
  let(:peer_id){ nil }
  let(:status){ Torrent::Transfer::Status::Running }
  let(:picker){ Torrent::PiecePicker::Sequential.new }

  subject do
    described_class.new(
      file: file,
      manager: manager,
      uploaded: uploaded,
      downloaded: downloaded,
      peer_id: peer_id,
      status: status,
      piece_picker: picker,
    )
  end

  describe "#transfer_ratio" do
    context "if nothing has been uploaded yet" do
      let(:uploaded){ 0u64 }
      it "returns 0" do
        expect(subject.transfer_ratio).to eq 0f64
      end
    end

    context "if nothing has been downloaded yet" do
      let(:downloaded){ 0u64 }
      it "returns 0" do
        expect(subject.transfer_ratio).to eq 0f64
      end
    end

    it "returns the uploaded divided by the downloaded amount" do
      expect(subject.transfer_ratio).to eq 0.10
    end
  end

  describe "#left" do
    it "returns the total_size minus the downloaded amount" do
      expect(subject.left).to eq file.total_size - downloaded
    end
  end

  # pending "#read_piece"
  # pending "#read_piece_for_upload"
  # pending "#write_piece"

  describe "#start" do
    it "calls the leech strategies #start method" do
      # expect(subject.leech_strategy).to receive(start)
      # subject.start
    end
  end
end
