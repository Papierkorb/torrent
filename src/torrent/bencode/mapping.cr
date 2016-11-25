module Torrent
  module Bencode
    macro mapping(properties, strict = false)
      {% for key, value in properties %}
        {% if value.is_a?(NamedTupleLiteral) %}
          {% properties[key][:var] = key %}
          {% properties[key][:key] = key unless properties[key].keys.map(&.stringify).includes?("key") %}
        {% else %}
          {% properties[key] = { type: value, var: key, key: key } %}
        {% end %}

      {% end %}

      {% for key, value in properties %}
        property {{ key.id }} : {{ value[:type] }}{{ (value[:nilable] ? "?" : "").id }}
      {% end %}

      def initialize(%pull : Torrent::Bencode::PullParser)
        {% for key, value in properties %}
          %found_{key.id} = false
          %var_{key.id} = nil
        {% end %}

        %pull.read_dictionary do
          key = String.new(%pull)
          case key
          {% for key, value in properties %}
          when {{ value[:key].id.stringify }}
            %found_{key.id} = true
            %var_{key.id} = {% if value[:converter] %}{{ value[:converter] }}.from_bencode(%pull){% else %}{{ value[:type] }}.new(%pull){% end %}
          {% end %}
          else
            {% if strict %}
              ::raise Torrent::Bencode::Error.new("Unknown attribute '#{key}'")
            {% else %}
              %pull.read_and_discard
            {% end %}
          end
        end

        {% for key, value in properties %}
        if %found_{key.id}
          @{{ key.id }} = %var_{key.id}.not_nil!
        else
          {% if value[:default] != nil %}
            @{{ key.id }} = {{ value[:default] }}
          {% elsif !value[:nilable] %}
            ::raise Torrent::Bencode::Error.new("Missing attribute '{{ key }}'")
          {% end %}
        end
        {% end %}
      end

      # Creates an instance from the *input*
      def self.from_bencode(input : Bytes)
        from_bencode(IO::Memory.new(input))
      end

      # ditto
      def self.from_bencode(input : IO)
        lexer = Torrent::Bencode::Lexer.new(input)
        parser = Torrent::Bencode::PullParser.new(lexer)
        new(parser)
      end

      # Writes the Bencoded data to *io*
      def to_bencode(io : IO) : IO
        io.print "d"

        {% mapping = { } of String => NamedTupleLiteral %}
        {% for key in properties.keys.sort %}
          {% mapping[properties[key][:key].id.stringify] = properties[key] %}
        {% end %}

        {% for key in mapping.keys.sort %}
          unless @{{ mapping[key][:var].id }}.nil?
            io.print "{{ key.id.size }}:{{ key.id }}"

            {% if mapping[key][:converter] %}
              {{ mapping[key][:converter] }}.to_bencode(@{{ mapping[key][:var].id }}.not_nil!, io)
            {% else %}
              @{{ mapping[key][:var].id }}.not_nil!.to_bencode(io)
            {% end %}
          end
        {% end %}

        io.print "e"
        io
      end
    end

    macro mapping(**properties)
      ::Torrent::Bencode.mapping({{ properties }})
    end
  end
end
