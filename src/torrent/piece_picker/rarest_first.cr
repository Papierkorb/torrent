module Torrent
  module PiecePicker
    # Implements a (in terms of BitTorrent) well-behaved piece picker, which
    # randomly picks a piece while giving precedence to pieces which are rare
    # in the swarm.
    class RarestFirst < Base
      BUCKETS = 4
      RANDOM_TRIES = 5

      alias Bucket = Array(UInt32)
      alias Buckets = StaticArray(Bucket, BUCKETS)

      def initialize(@transfer : Torrent::Transfer)
        @buckets = Buckets.new{ Bucket.new }
        @no_peer = Bucket.new
        @log = Util::Logger.new("PiecePicker/RarestFirst")

        @transfer.manager.peer_list.peer_added.on do |peer|
          peer.bitfield_received.on{ mark_dirty }
          peer.have_received.on{|piece| handle_have piece}
        end

        @transfer.manager.peer_list.peer_removed.on{|_peer| mark_dirty}
      end

      # Returns a list of pieces which are provided by no peer.
      def pieces_without_peers : Bucket
        buckets
        @no_peer
      end

      def pick_piece(peer : Client::Peer) : UInt32?
        buckets.each do |bucket|
          next if bucket.empty?
          if idx = pick_from_bucket(bucket, peer)
            return take_at(bucket, idx)
          end
        end

        nil # None found.
      end

      def unpick_piece(piece : UInt32)
        buckets

        count = count_peers_having_piece @transfer.manager.peers, piece
        put_piece_into_bucket(piece, count)
      end

      def mark_dirty
        @dirty = true
      end

      private def take_at(array, index)
        array.swap index, array.size - 1
        array.pop
      end

      private def buckets
        rebuild_buckets @transfer.manager.peers if @dirty
        @buckets
      end

      # Does a partial update, increasing the commonness of *piece*
      private def handle_have(piece : UInt32)
        buckets

        if @no_peer.delete piece
          @buckets[0] << piece # No peer had the piece before
        else
          @buckets.each_with_index do |bucket, bucket_idx|
            # Skip the last bucket.
            break if bucket_idx >= @buckets.size - 1

            if bucket.delete piece
              @buckets[bucket_idx + 1] << piece
              break
            end
          end
        end
      end

      private def pick_from_bucket(bucket, peer)
        pick_random(bucket, peer) || pick_linear(bucket, peer)
      end

      private def pick_random(bucket, peer)
        Math.min(bucket.size, RANDOM_TRIES).times do
          idx = rand(bucket.size)
          return idx if peer.bitfield[bucket[idx]] == true
        end

        nil
      end

      private def pick_linear(bucket, peer)
        bucket.each_with_index do |piece, idx|
          return idx if peer.bitfield[piece]
        end

        nil
      end

      private def count_peers_having_piece(peers, piece_index)
        count = peers.map{|peer| peer.bitfield[piece_index].hash}.sum
        return BUCKETS if count > BUCKETS
        count
      end

      private def put_piece_into_bucket(piece_index, count)
        if count > 0
          @buckets[count - 1] << piece_index
        else
          @no_peer << piece_index
        end
      end

      private def rebuild_buckets(peers : Enumerable(Client::Peer))
        @dirty = false
        @buckets = Buckets.new{ Bucket.new }
        @no_peer = Bucket.new

        @transfer.piece_count.to_u32.times do |piece_index|
          next if @transfer.requests.private_bitfield[piece_index]

          count = count_peers_having_piece(peers, piece_index)
          put_piece_into_bucket piece_index, count
        end

        @log.info "Rebuilt buckets. #{@no_peer.size} pieces without any peers, other buckets have #{@buckets.map(&.size)} pieces each"
      end
    end
  end
end
