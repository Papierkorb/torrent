require "../../spec_helper"

Spec2.describe Torrent::Dht::Dispatcher do
  subject{ described_class.new }

  describe "#add" do
    it "adds the method" do
      func = ->(a : Torrent::Dht::Node, b : Torrent::Dht::Structure::Query){ }
      subject.add "foo", func
      expect(subject.methods["foo"]).to eq func
    end
  end

  describe "#add(&block)" do
    it "adds the method" do
      subject.add("foo"){ }
      expect(subject.methods["foo"]?).not_to be_nil
    end
  end

  describe "#invoke_method" do
    let(:args){ { "one" => Torrent::Bencode::Any.new(1) } }
    let(:query){ Torrent::Dht::Structure::Query.new("ab".to_slice, "foo", args) }
    let(:node){ node 6 }
    context "if the method exists" do
      it "calls the lambda and returns true" do
        passed_node = nil
        passed_query = nil

        subject.add("foo") do |n, q|
          passed_node = n
          passed_query = q
        end

        expect(subject.invoke_method node, query).to be_true
        expect(passed_node).to be node
        expect(passed_query).to eq query
      end
    end

    context "if the method does NOT exist" do
      it "returns false" do
        passed_node = nil
        passed_query = nil

        expect(subject.invoke_method node, query).to be_false
        expect(passed_node).to be_nil
        expect(passed_query).to be_nil
      end
    end
  end

  describe "#remote_invocation" do
    let(:args){ { "one" => Torrent::Bencode::Any.new(1) } }
    let(:query){ Torrent::Dht::Structure::Query.new("ab".to_slice, "foo", args) }
    let(:node){ node 6 }

    context "if the method exists" do
      it "calls the lambda" do
        passed_node = nil
        passed_query = nil

        subject.add("foo") do |n, q|
          passed_node = n
          passed_query = q
        end

        expect(subject.remote_invocation node, query).to be_true
        expect(passed_node).to be node
        expect(passed_query).to eq query
      end

      context "and the handler raises an error" do
        it "sends a generic server error" do
          subject.add("foo"){|_n, _q| raise "Oh noes"}
          expect(subject.remote_invocation node, query).to be_false

          expect(node.sent.size).to eq 1
          e = node.sent.first.as(Torrent::Dht::Structure::Error)
          expect(e.code).to eq 202
          expect(e.message).to eq "A Server Error Occured"
        end
      end

      context "and the handler raises a QueryHandlerError" do
        it "sends a generic server error" do
          subject.add("foo") do |_n, _q|
            raise Torrent::Dht::QueryHandlerError.new("Oh noes", Torrent::Dht::ErrorCode::Protocol, "U Done Goofd")
          end

          expect(subject.remote_invocation node, query).to be_false

          expect(node.sent.size).to eq 1
          e = node.sent.first.as(Torrent::Dht::Structure::Error)
          expect(e.code).to eq 203
          expect(e.message).to eq "U Done Goofd"
        end
      end
    end

    context "if the method does NOT exist" do
      it "sends an unknown method error" do
        passed_node = nil
        passed_args = nil

        expect(subject.remote_invocation node, query).to be_false
        expect(node.sent.first).to be_a Torrent::Dht::Structure::Error
        e = node.sent.first.as(Torrent::Dht::Structure::Error)

        expect(e.transaction).to eq "ab".to_slice
        expect(e.code).to eq 204

        expect(passed_node).to be_nil
        expect(passed_args).to be_nil
      end
    end
  end
end
