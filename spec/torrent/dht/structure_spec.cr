require "../../spec_helper"

Spec2.describe Torrent::Dht::Structure::Message do
  describe ".from" do
    subject{ described_class.from Torrent::Bencode.load packet.to_slice }

    context "if y == 'q'" do
      let(:packet){ "d1:t2:xy1:y1:q1:q3:abc1:ad3:foo3:baree" }

      it "builds a Query" do
        expect(subject).to be_a(Torrent::Dht::Structure::Query)

        query = subject.as(Torrent::Dht::Structure::Query)
        expect(query.transaction).to eq "xy".to_slice
        expect(query.method).to eq "abc"
        expect(query.args).to eq({ "foo" => Torrent::Bencode::Any.new("bar") })
      end
    end

    context "if y == 'r'" do
      let(:packet){ "d1:t2:xy1:y1:r1:rd3:foo3:baree" }

      it "builds a Response" do
        expect(subject).to be_a(Torrent::Dht::Structure::Response)

        response = subject.as(Torrent::Dht::Structure::Response)
        expect(response.transaction).to eq "xy".to_slice
        expect(response.data).to eq({ "foo" => Torrent::Bencode::Any.new("bar") })
      end
    end

    context "if y == 'e'" do
      let(:packet){ "d1:t2:xy1:y1:e1:eli201e5:helloee" }

      it "builds an Error" do
        expect(subject).to be_a(Torrent::Dht::Structure::Error)

        error = subject.as(Torrent::Dht::Structure::Error)
        expect(error.transaction).to eq "xy".to_slice
        expect(error.code).to eq 201
        expect(error.message).to eq "hello"
      end
    end

    context "else" do
      let(:packet){ "d1:t2:xy1:y1:d1:rd3:foo3:baree" }
      it "raises an ArgumentError" do
        expect{ subject }.to raise_error(ArgumentError, match /unknown type/i)
      end
    end
  end
end

Spec2.describe Torrent::Dht::Structure::Query do
  subject{ described_class.new("xyz".to_slice, "foo", { "bar" => Torrent::Bencode::Any.new("baz") }) }

  describe "#response" do
    it "returns a Response" do
      r = subject.response({ "one" => Torrent::Bencode::Any.new(2) })
      expect(r).to be_a Torrent::Dht::Structure::Response
      expect(r.transaction).to eq "xyz".to_slice
      expect(r.data).to eq({ "one" => Torrent::Bencode::Any.new(2) })
    end
  end

  describe "#error(ErrorCode)" do
    context "if a message is given" do
      it "uses the given message" do
        e = subject.error(Torrent::Dht::ErrorCode::Server, "oh noes")
        expect(e).to be_a Torrent::Dht::Structure::Error
        expect(e.transaction).to eq "xyz".to_slice
        expect(e.code).to eq Torrent::Dht::ErrorCode::Server.value
        expect(e.message).to eq "oh noes"
      end
    end

    context "if NO message is given" do
      it "uses the default message" do
        e = subject.error(Torrent::Dht::ErrorCode::Server)
        expect(e).to be_a Torrent::Dht::Structure::Error
        expect(e.transaction).to eq "xyz".to_slice
        expect(e.code).to eq Torrent::Dht::ErrorCode::Server.value
        expect(e.message).to eq "A Server Error Occured"
      end
    end
  end

  describe "#error(Int32)" do
    it "returns an Error" do
      e = subject.error(123, "something happened")
      expect(e).to be_a Torrent::Dht::Structure::Error
      expect(e.transaction).to eq "xyz".to_slice
      expect(e.code).to eq 123
      expect(e.message).to eq "something happened"
    end
  end
end
