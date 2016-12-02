require "../../spec_helper"

private def receive_now(subject, t, packet : String)
  data = Bytes.new(packet.size)
  data.copy_from packet.to_slice
  data[6] = t[0]
  data[7] = t[1]
  subject.handle_incoming data
end

private def receive_later(subject, packet : String)
  spawn do
    begin
      t = subject.transactions.first
      receive_now subject, t, packet
    rescue err
      puts "Fatal Error: (#{err.class}) #{err}"
      puts err.backtrace.join('\n')
      exit 127
    end
  end
end

Spec2.describe Torrent::Dht::Node do
  let(:my_id){ BigInt.new "275128666552365745816705927789606773184219527225" }
  let(:remote_id){ BigInt.new "555966236078694990583973964953671459193246344036" }

  # "01234567890123456789"
  let(:my_id_bytes){ Torrent::Util::Gmp.export_sha1 my_id }

  # "abcdef0123456789abcd"
  let(:remote_id_bytes){ Torrent::Util::Gmp.export_sha1 remote_id }

  let(:last_seen){ Time.now - 20.minutes }
  subject{ node remote_id - 100 }
  before{ subject.last_seen = last_seen }

  describe "#hash" do
    it "compares based on the id" do
      expect(node(5).hash).to eq node(5).hash
    end
  end

  describe "#handle_incoming" do
    let!(:message_received){ Cute.spy subject, message_received(message : Torrent::Dht::Structure::Message) }
    let!(:query_received){ Cute.spy subject, query_received(query : Torrent::Dht::Structure::Query) }
    let!(:response_received){ Cute.spy subject, response_received(query : Torrent::Dht::Structure::Response) }
    let!(:error_received){ Cute.spy subject, error_received(query : Torrent::Dht::Structure::Error) }

    let(:message){ Torrent::Dht::Structure::Message.from Torrent::Bencode.load packet.to_slice }

    context "if it's a query" do
      let(:packet){ "d1:t2:xy1:y1:q1:q3:abc1:ad3:foo3:baree" }

      it "emits query_received" do
        subject.receive packet
        expect(message_received).to eq [ message ]
        expect(query_received).to eq [ message ]
        expect(response_received.empty?).to be_true
        expect(error_received.empty?).to be_true
      end
    end

    context "if it's a response" do
      let(:packet){ "d1:t2:xy1:y1:r1:rd3:foo3:baree" }

      it "emits response_received" do
        subject.receive packet
        expect(message_received).to eq [ message ]
        expect(query_received.empty?).to be_true
        expect(response_received).to eq [ message ]
        expect(error_received.empty?).to be_true
      end
    end

    context "if it's a error" do
      let(:packet){ "d1:t2:xy1:y1:e1:eli201e5:helloee" }

      it "emits error_received" do
        subject.receive packet
        expect(message_received).to eq [ message ]
        expect(query_received.empty?).to be_true
        expect(response_received.empty?).to be_true
        expect(error_received).to eq [ message ]
      end
    end
  end

  describe "#remote_call question-mark" do
    let(:args){ { "five" => Torrent::Bencode::Any.new(5) } }

    context "if the response is received" do
      let(:packet){ "d1:t2:xy1:y1:r1:rd3:foo3:baree" }

      it "returns the response" do
        receive_later(subject, packet)
        response = subject.remote_call?("foo", args)
        expect(subject.last_seen).not_to eq last_seen
        expect(subject.health.good?).to be_true

        expect(response).to be_a Torrent::Dht::Structure::Response
        r = response.as(Torrent::Dht::Structure::Response)
        expect(r.data).to eq({ "foo" => Torrent::Bencode::Any.new("bar") })
      end
    end

    context "if an error is received" do
      let(:packet){ "d1:t2:xy1:y1:e1:eli201e5:helloee" }

      it "returns the error" do
        receive_later(subject, packet)
        error = subject.remote_call?("foo", args)
        expect(subject.last_seen).not_to eq last_seen
        expect(subject.health.good?).to be_true

        expect(error).to be_a Torrent::Dht::Structure::Error
        e = error.as(Torrent::Dht::Structure::Error)
        expect(e.code).to eq 201
        expect(e.message).to eq "hello"
      end
    end

    context "if the timeout is triggered" do
      it "returns nil" do
        result = subject.remote_call?("foo", args, timeout: 10.milliseconds)
        expect(result).to be_nil
        expect(subject.last_seen).to eq last_seen
        expect(subject.health.questionable?).to be_true
      end

      context "and the health is questionable" do
        it "goes to bad" do
          subject.health = Torrent::Dht::Node::Health::Questionable
          result = subject.remote_call?("foo", args, timeout: 10.milliseconds)
          expect(result).to be_nil
          expect(subject.last_seen).to eq last_seen
          expect(subject.health.bad?).to be_true
        end
      end
    end
  end

  describe "#remote_call" do
    let(:args){ { "five" => Torrent::Bencode::Any.new(5) } }

    context "if the response is received" do
      let(:packet){ "d1:t2:xy1:y1:r1:rd3:foo3:baree" }

      it "returns the response" do
        receive_later(subject, packet)
        response = subject.remote_call("foo", args)

        expect(response).to eq({ "foo" => Torrent::Bencode::Any.new("bar") })
      end
    end

    context "if an error is received" do
      let(:packet){ "d1:t2:xy1:y1:e1:eli201e5:helloee" }

      it "raises the error" do
        receive_later(subject, packet)
        expect{ subject.remote_call("foo", args) }.to raise_error(Torrent::Dht::RemoteCallError, match /remote call error to "foo": 201 - hello/i)
      end
    end

    context "if the timeout is triggered" do
      it "returns nil" do
        expect{ subject.remote_call("foo", args, timeout: 10.milliseconds) }.to raise_error(Torrent::Dht::CallTimeout)
      end
    end

    context "if multiple requests are running concurrently" do
      let(:packet){ "d1:t2:xy1:y1:r1:rd3:foo3:baree" }

      it "doesn't break" do
        responses = Array(Int32).new

        100.times do
          spawn{ responses << subject.remote_call("foo", args)["n"].to_i.to_i32 }
        end

        until subject.transactions.size == 100
          sleep 10.milliseconds
        end

        trans = subject.transactions.dup
        (0..99).to_a.shuffle.each do |idx|
          r = Torrent::Dht::Structure::Response.new(trans[idx], { "n" => Torrent::Bencode::Any.new(idx) })
          subject.receive r.to_bencode
        end

        until responses.size == 100
          sleep 10.milliseconds
        end

        expect(responses.sort).to eq (0..99).to_a
      end
    end
  end

  describe "#ping" do
    context "on success" do
      it "returns the remote nodes id and sets the RTT" do
        receive_later subject, "d1:t2:xy1:y1:r1:rd2:id20:abcdef0123456789abcdee"
        expect(subject.ping my_id).to eq remote_id

        expect(subject.last_seen).not_to eq last_seen
        expect(subject.rtt).to_be < 1.second
        expect(subject.sent.size).to eq 1
        expect(subject.sent.first).to be_a(Torrent::Dht::Structure::Query)

        q = subject.sent.first.as(Torrent::Dht::Structure::Query)
        expect(q.method).to eq "ping"
        expect(q.args).to eq({ "id" => Torrent::Bencode::Any.new(my_id_bytes) })
      end
    end

    context "on error response" do
      it "returns nil" do
        receive_later subject, "d1:t2:xy1:y1:e1:eli201e2:?!ee"
        expect(subject.last_seen).to eq last_seen
        expect(subject.ping my_id).to be_nil

        expect(subject.sent.size).to eq 1
        expect(subject.sent.first).to be_a(Torrent::Dht::Structure::Query)
      end
    end
  end

  describe "#find_node" do
    it "returns the nodes" do
      receive_later subject, "d1:t2:xy1:y1:r1:rd2:id20:abcdef0123456789abcd5:nodes26:01234567890123456789abcd5aee"
      expect(subject.find_node my_id, remote_id).to eq [
        Torrent::Dht::NodeAddress.new("97.98.99.100", 13665u16, my_id, false)
      ]

      expect(subject.sent.size).to eq 1
      expect(subject.sent.first).to be_a(Torrent::Dht::Structure::Query)

      q = subject.sent.first.as(Torrent::Dht::Structure::Query)
      expect(q.method).to eq "find_node"
      expect(q.args).to eq({
        "id" => Torrent::Bencode::Any.new(my_id_bytes),
        "target" => Torrent::Bencode::Any.new(remote_id_bytes),
      })
    end
  end

  describe "#get_peers" do
    context "if reply contains both nodes and peers" do
      it "returns the nodes, peers and sets the token" do
        receive_later subject, "d1:t2:xy1:y1:r1:rd2:id20:abcdef0123456789abcd5:nodes26:01234567890123456789abcd5a6:valuesl6:idhtnme5:token3:abcee"
        expect(subject.get_peers my_id, remote_id).to eq({[
          Torrent::Dht::NodeAddress.new("97.98.99.100", 13665u16, my_id, false),
          ], [
            Torrent::Structure::PeerInfo.new("105.100.104.116", 28269, false),
            ]})

        expect(subject.peers_token).to eq "abc".to_slice
        expect(subject.sent.size).to eq 1
        expect(subject.sent.first).to be_a(Torrent::Dht::Structure::Query)

        q = subject.sent.first.as(Torrent::Dht::Structure::Query)
        expect(q.method).to eq "get_peers"
        expect(q.args).to eq({
          "id" => Torrent::Bencode::Any.new(my_id_bytes),
          "info_hash" => Torrent::Bencode::Any.new(remote_id_bytes),
        })
      end
    end

    context "if reply contains peers only" do
      it "returns the peers and sets the token" do
        receive_later subject, "d1:t2:xy1:y1:r1:rd2:id20:abcdef0123456789abcd6:valuesl6:idhtnme5:token3:abcee"
        expect(subject.get_peers my_id, remote_id).to eq({
          Array(Torrent::Dht::NodeAddress).new, [
            Torrent::Structure::PeerInfo.new("105.100.104.116", 28269, false),
        ]})

        expect(subject.peers_token).to eq "abc".to_slice
        expect(subject.sent.size).to eq 1
        expect(subject.sent.first).to be_a(Torrent::Dht::Structure::Query)

        q = subject.sent.first.as(Torrent::Dht::Structure::Query)
        expect(q.method).to eq "get_peers"
        expect(q.args).to eq({
          "id" => Torrent::Bencode::Any.new(my_id_bytes),
          "info_hash" => Torrent::Bencode::Any.new(remote_id_bytes),
        })
      end
    end

    context "if reply contains nodes only" do
      it "returns the nodes and sets the token" do
        receive_later subject, "d1:t2:xy1:y1:r1:rd2:id20:abcdef0123456789abcd5:nodes26:abcdef0123456789abcdabcd5a5:token3:abcee"
        expect(subject.get_peers my_id, remote_id).to eq({[
          Torrent::Dht::NodeAddress.new("97.98.99.100", 13665u16, remote_id, false),
          ], Array(Torrent::Structure::PeerInfo).new,
        })

        expect(subject.peers_token).to eq "abc".to_slice
        expect(subject.sent.size).to eq 1
        expect(subject.sent.first).to be_a(Torrent::Dht::Structure::Query)

        q = subject.sent.first.as(Torrent::Dht::Structure::Query)
        expect(q.method).to eq "get_peers"
        expect(q.args).to eq({
          "id" => Torrent::Bencode::Any.new(my_id_bytes),
          "info_hash" => Torrent::Bencode::Any.new(remote_id_bytes),
        })
      end
    end
  end

  describe "#announce_peer" do
    context "if the peer token is NOT set" do
      it "raises an Error" do
        expect{ subject.announce_peer my_id, remote_id, 123u16 }.to raise_error(Torrent::Dht::Error, match /no peers_token/i)
      end
    end

    context "if the peer token is set" do
      before{ subject.peers_token = "abc".to_slice }

      it "sends a announce_peer query" do
        receive_later subject, "d1:t2:xy1:y1:r1:rd2:id20:abcdef0123456789abcdee"
        subject.announce_peer my_id, remote_id, 4567u16

        expect(subject.peers_token).to eq "abc".to_slice
        expect(subject.sent.size).to eq 1
        expect(subject.sent.first).to be_a(Torrent::Dht::Structure::Query)

        q = subject.sent.first.as(Torrent::Dht::Structure::Query)
        expect(q.method).to eq "announce_peer"
        expect(q.args).to eq({
          "id" => Torrent::Bencode::Any.new(my_id_bytes),
          "info_hash" => Torrent::Bencode::Any.new(remote_id_bytes),
          "implied_port" => Torrent::Bencode::Any.new(0),
          "port" => Torrent::Bencode::Any.new(4567),
          "token" => Torrent::Bencode::Any.new("abc".to_slice),
        })
      end
    end
  end

  describe "#refresh_if_needed" do
    context "if health is already bad" do
      before{ subject.health = Torrent::Dht::Node::Health::Bad }
      it "returns false" do
        expect(subject.refresh_if_needed my_id).to be_false
      end
    end

    context "if last_seen has not timeouted yet" do
      before{ subject.last_seen = Time.now }
      it "returns true" do
        expect(subject.refresh_if_needed my_id).to be_true
      end
    end

    context "if the remote node responds to a ping" do
      it "returns true" do
        receive_later subject, "d1:t2:xy1:y1:r1:rd2:id20:abcdef0123456789abcdee"
        expect(subject.refresh_if_needed my_id).to be_true
        expect(subject.last_seen).not_to eq last_seen
        expect(subject.sent.size).to eq 1

        q = subject.sent.first.as(Torrent::Dht::Structure::Query)
        expect(q.method).to eq "ping"
      end
    end

    context "if the remote node does not respond" do
      let(:timeout){ 10.milliseconds }

      context "a second time" do
        before{ subject.health = Torrent::Dht::Node::Health::Questionable }
        it "returns false" do
          expect(subject.refresh_if_needed my_id, timeout).to be_false
          expect(subject.last_seen).not_to eq last_seen
          expect(subject.health.bad?).to be_true
        end
      end

      context "but responds the second time" do
        before{ subject.health = Torrent::Dht::Node::Health::Questionable }
        it "returns true" do
          receive_later subject, "d1:t2:xy1:y1:r1:rd2:id20:abcdef0123456789abcdee"
          expect(subject.refresh_if_needed my_id).to be_true
          expect(subject.last_seen).not_to eq last_seen
          expect(subject.health.good?).to be_true
        end
      end

      it "returns true" do
        expect(subject.refresh_if_needed my_id, timeout).to be_true
        expect(subject.last_seen).not_to eq last_seen
        expect(subject.health.questionable?).to be_true
      end
    end

    context "if the remote node responds with the wrong id" do
      it "returns false" do
        receive_later subject, "d1:t2:xy1:y1:r1:rd2:id20:77777777777777777777ee"
        expect(subject.refresh_if_needed my_id).to be_false
        expect(subject.health.bad?).to be_true
      end
    end
  end
end
