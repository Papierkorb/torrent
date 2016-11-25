require "../../spec_helper"

Spec2.describe Torrent::Dht::DefaultRpcMethods do
  let(:my_id){ BigInt.new "85968058272638546411811" }
  let(:remote_id){ BigInt.new "555966236078694990583973964953671459193246344036" }
  let(:my_id_bytes){ Torrent::Util::Gmp.export_sha1 my_id }
  let(:remote_id_bytes){ Torrent::Util::Gmp.export_sha1 remote_id }

  let(:log){ Torrent::Util::Logger.new("Foo") }
  let(:manager){ Torrent::Dht::Manager.new my_id }
  let(:dispatcher){ manager.dispatcher }

  let(:node){ node 6 }
  let(:node_compact_addr) do
    Torrent::Dht::NodeAddress.to_compact({ node.to_address })
  end

  let(:args){ { "id" => Torrent::Bencode::Any.new(Torrent::Util::Gmp.export_sha1 node.id) } }
  let(:sent){ node.sent }

  describe "ping" do
    it "sends a ping response" do
      expect(dispatcher.invoke_method node, query("ping", args)).to be_true
      expect(sent.size).to eq 1
      expect(sent.first).to eq response({ "id" => Torrent::Bencode::Any.new(my_id_bytes) })
    end
  end

  describe "find_node" do
    before{ manager.nodes.try_add node }
    it "sends a find_node response" do
      args["target"] = Torrent::Bencode::Any.new(remote_id_bytes)
      expect(dispatcher.invoke_method node, query("find_node", args)).to be_true
      expect(sent.size).to eq 1
      expect(sent.first).to eq response({
        "id" => Torrent::Bencode::Any.new(my_id_bytes),
        "nodes" => Torrent::Bencode::Any.new(node_compact_addr),
      })
    end
  end

  describe "get_peers" do
    before{ manager.nodes.try_add node }

    context "if there are peers" do
      let(:peers) do
        [
          Torrent::Bencode::Any.new(Bytes.new(6, &.to_u8)),
          Torrent::Bencode::Any.new(Bytes.new(6, &.to_u8.+(6))),
        ]
      end

      before do
        manager.add_torrent_peer node, remote_id_bytes, "0.1.2.3", 1029u16
        manager.add_torrent_peer node, remote_id_bytes, "6.7.8.9", 2571u16
      end

      it "replies with peers" do
        args["info_hash"] = Torrent::Bencode::Any.new remote_id_bytes
        expect(dispatcher.invoke_method node, query("get_peers", args)).to be_true
        expect(sent.size).to eq 1
        r = sent.first.as(Torrent::Dht::Structure::Response).data

        expect(r.keys.sort).to eq [ "id", "token", "values" ]
        expect(r["id"]).to eq Torrent::Bencode::Any.new(my_id_bytes)
        expect(r["token"].to_slice.size).to_be > 1
        expect(r["values"].to_a.size).to eq 2
        r["values"].to_a.each{|p| peers.delete p}
        expect(peers.empty?).to be_true
      end
    end

    context "if there are NO peers" do
      it "replies with nodes" do
        args["info_hash"] = Torrent::Bencode::Any.new remote_id_bytes
        expect(dispatcher.invoke_method node, query("get_peers", args)).to be_true
        expect(sent.size).to eq 1
        r = sent.first.as(Torrent::Dht::Structure::Response).data

        expect(r.keys.sort).to eq [ "id", "nodes", "token" ]
        expect(r["id"]).to eq Torrent::Bencode::Any.new(my_id_bytes)
        expect(r["token"].to_slice.size).to_be > 1
        expect(r["nodes"].to_slice).to eq node_compact_addr
      end
    end
  end

  describe "announce_peer" do
    let(:token){ "AbCd".to_slice }
    let(:implied_port){ false }
    let(:peer_list){ manager.peers.first }

    before do
      args["info_hash"] = Torrent::Bencode::Any.new remote_id_bytes
      args["implied_port"] = Torrent::Bencode::Any.new implied_port
      args["port"] = Torrent::Bencode::Any.new 7777

      # Don't use let(:token) here.
      args["token"] = Torrent::Bencode::Any.new "AbCd".to_slice

      node.remote_token = token
    end

    context "if the token is correct" do
      context "if implied_port is 1" do
        let(:implied_port){ true }

        it "stores the peer using the nodes UDP port" do
          expect(dispatcher.invoke_method node, query("announce_peer", args)).to be_true
          expect(sent.size).to eq 1
          expect(sent.first).to eq response({ "id" => Torrent::Bencode::Any.new(my_id_bytes) })

          expect(peer_list.peers.size).to eq 1
          expect(peer_list.peers.first[1]).to eq Slice[ 1u8, 2u8, 3u8, 4u8, 0x30u8, 0x39u8 ]
        end
      end

      context "if implied_port is 0" do
        it "stores the peer" do
          expect(dispatcher.invoke_method node, query("announce_peer", args)).to be_true
          expect(sent.size).to eq 1
          expect(sent.first).to eq response({ "id" => Torrent::Bencode::Any.new(my_id_bytes) })
          expect(peer_list.peers.size).to eq 1
          expect(peer_list.peers.first[1]).to eq Slice[ 1u8, 2u8, 3u8, 4u8, 0x1Eu8, 0x61u8 ]
        end
      end
    end

    context "if the token is NOT correct" do
      let(:token){ "WRONG".to_slice }

      it "sends an error" do
        expect(dispatcher.invoke_method node, query("announce_peer", args)).to be_true
        expect(sent.size).to eq 1
        expect(sent.first).to eq error(201, "Wrong Token")
      end
    end
  end
end
