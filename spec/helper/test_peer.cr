# Mock peer implementation
class TestPeer < Torrent::Client::Peer
  struct Packet
    getter type : UInt8
    getter payload : Bytes
    getter? ping : Bool

    def id
      Torrent::Client::Wire::MessageType.from_value @type
    end

    def initialize(@type, payload, @ping = false)
      @payload = Bytes.new(payload.size)
      @payload.copy_from(payload)
    end
  end

  # Captured, outgoing packets
  getter packets : Array(Packet)

  # Make some private fields writable for testing
  setter bitfield
  setter extension_protocol
  setter fast_extension

  def initialize(transfer)
    super(transfer.manager, transfer)
    @packets = Array(Packet).new
  end

  def send_packet(type : UInt8, payload : Bytes? = nil)
    payload ||= Bytes.new(0)
    @packets << Packet.new(type, payload)
  end

  def send_data(data : Bytes)
    if data.size == 0 # Detect PING
      @packets << Packet.new(0u8, data, true)
    else
      @packets << Packet.new(data[0], data + 1)
    end
  end

  def send_data(&block : -> Bytes?)
    result = block.call
    send_data(result) if result.is_a?(Bytes)
  end

  def address : String
    "123.123.123.123"
  end

  def port : UInt16
    12345u16
  end

  def run_once
    # Nothing to do.
  end
end
