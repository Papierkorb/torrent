require "../spec_helper"

Spec2.describe Torrent::Transfer do
  let(:file){ Torrent::File.read("#{__DIR__}/../fixtures/debian.torrent") }
  let(:file_manager){ Torrent::FileManager::FileSystem.new("/tmp") }
  let(:manager){ Torrent::Manager::Transfer.new(file_manager) }

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
      # TODO: Compiler bug if the following line is not commented.
      # subject.start
    end
  end

  describe "#change_status" do
    let!(:status_changed){ Cute.spy subject, status_changed(status : Torrent::Transfer::Status) }
    let!(:download_completed){ Cute.spy subject, download_completed }

    context "if the new status is the current status" do
      it "does nothing" do
        subject.change_status status
        expect(status_changed.empty?).to be_true
        expect(download_completed.empty?).to be_true
      end
    end

    context "if the status is 'Completed'" do
      let(:new_status){ Torrent::Transfer::Status::Completed }
      it "also emits download_completed" do
        subject.change_status new_status
        expect(subject.status).to eq new_status
        expect(status_changed).to eq [ new_status ]
        expect(download_completed).to eq [ nil ]
      end
    end

    context "if the status is something else" do
      let(:new_status){ Torrent::Transfer::Status::Stopped }
      it "emits status_changed" do
        subject.change_status new_status
        expect(subject.status).to eq new_status
        expect(status_changed).to eq [ new_status ]
        expect(download_completed.empty?).to be_true
      end
    end
  end

  describe "#save" do
    it "returns a hash containing all persistable data" do
      expect(subject.save).to eq({
        "uploaded" => uploaded,
        "downloaded" => downloaded,
        "peer_id" => subject.peer_id,
        "status" => status.to_s,
        "info_hash" => file.info_hash.hexstring,
        "bitfield_size" => file.piece_count,
        "bitfield_data" => ("00" * (file.piece_count / 8 + 1)),
      })
    end
  end

  describe "#initialize(resume)" do
    let(:resume){ subject.save }
    let(:resume_peer_id){ true }

    let(:resumed_subject) do
      described_class.new(
        resume: resume,
        file: file,
        manager: manager,
        piece_picker: picker,
        peer_id: resume_peer_id,
      )
    end

    context "if the info_hash does not match" do
      it "raises" do
        resume["info_hash"] = "not_correct"
        expect{ resumed_subject }.to raise_error(ArgumentError, match /wrong file/i)
      end
    end

    context "if the bitfield_size does not match" do
      it "raises" do
        resume["bitfield_size"] = file.piece_count - 1
        expect{ resumed_subject }.to raise_error(ArgumentError, match /wrong bitfield_size/i)
      end
    end

    context "if the peer_id is a string" do
      let(:resume_peer_id){ "my-peer-id" }
      it "uses it instead of the resume peer_id" do
        expect(resumed_subject.peer_id).to eq resume_peer_id
      end
    end

    context "if the peer_id is true" do
      let(:resume_peer_id){ true }
      it "uses the resume peer_id" do
        expect(resumed_subject.peer_id).to eq resume["peer_id"].as(String)
      end
    end

    context "if the peer_id is false" do
      let(:resume_peer_id){ false }
      it "generates a new peer-id" do
        expect(resumed_subject.peer_id).not_to eq resume_peer_id
        expect(resumed_subject.peer_id).to match /^-CR/i
      end
    end

    it "restores the transfer" do
      expect(resumed_subject.downloaded).to eq downloaded
      expect(resumed_subject.uploaded).to eq uploaded
      expect(resumed_subject.status).to eq status
      expect(resumed_subject.requests.public_bitfield).to eq subject.requests.public_bitfield
    end
  end
end
