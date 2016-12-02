def node(id)
  TestNode.new(100 + id.to_big_i)
end

def query(method, args, transaction = "F00".to_slice)
  Torrent::Dht::Structure::Query.new(transaction, method, args)
end

def response(data, transaction = "F00".to_slice)
  Torrent::Dht::Structure::Response.new(transaction, data)
end

def error(code, message, transaction = "F00".to_slice)
  Torrent::Dht::Structure::Error.new(transaction, code, message)
end

# Mock DHT node
class TestNode < Torrent::Dht::Node
  getter sent : Array(Torrent::Dht::Structure::Message)
  setter peers_token
  setter last_seen
  setter health

  def initialize(id)
    super

    @sent = Array(Torrent::Dht::Structure::Message).new
  end

  def remote_address
    Socket::IPAddress.new(Socket::Family::INET, "1.2.3.4", 12345)
  end

  def close
    # Nothing.
  end

  def send(message : Torrent::Dht::Structure::Message)
    sent << message
  end

  def receive(packet : String)
    handle_incoming packet.to_slice
  end

  def receive(packet : Bytes)
    handle_incoming packet
  end

  def transactions
    @calls.keys
  end
end
