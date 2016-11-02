module Torrent
  module Util
    abstract struct NetworkOrderStruct(T)
      property inner : T

      def initialize(@inner : T)
      end

      def initialize
        @inner = T.new
      end

      # Casts *self* to `Bytes`.  Caution: This will *not* copy any data, the
      # returned slice will point to the data structure.
      def to_bytes : Bytes
        Bytes.new(pointerof(@inner).as(UInt8*), instance_sizeof(T))
      end

      def self.from(data : Bytes) : self
        inner = uninitialized T
        data.copy_to(pointerof(inner).as(UInt8*), instance_sizeof(T))
        new(inner)
      end

      def write_to(io : IO)
        io.write to_bytes
      end

      def self.from(io : IO) : self
        inner = uninitialized T
        buf = Bytes.new(pointerof(inner).as(UInt8*), instance_sizeof(T))
        io.read_fully(buf)
        new(inner)
      end

      # Declares the fields in the underlying structure.  For integer types,
      # automatic conversion from host byte order to network byte order is done
      # when reading/writing a field.  All other types are passed-through.
      macro fields(*type_decls)
        {% for type_decl in type_decls %}
          {% if %w[ Int16 Int32 Int64 UInt16 UInt32 UInt64 ].includes?(type_decl.type.id.stringify) %}
            def {{ type_decl.var.id }} : {{ type_decl.type }}
              Torrent::Util::Endian.to_host(@inner.{{ type_decl.var.id }})
            end

            def {{ type_decl.var.id }}=(val : {{ type_decl.type }})
              @inner.{{ type_decl.var.id }} = Torrent::Util::Endian.to_network(val)
            end
          {% else %}
            def {{ type_decl.var.id }} : {{ type_decl.type }}
              @inner.{{ type_decl.var.id }}
            end

            def {{ type_decl.var.id }}=(val : {{ type_decl.type }})
              @inner.{{ type_decl.var.id }} = val
            end
          {% end %}
        {% end %}

        def initialize(@inner)
        end

        def initialize
          @inner = T.new
        end

        def initialize(
          {% for decl in type_decls %}{{ decl.var.id }} : {{ decl.type }}, {% end %}
        )
          @inner = T.new

          {% for decl in type_decls %}
            @inner.{{ decl.var.id }} = {% if %w[ Int16 Int32 Int64 UInt16 UInt32 UInt64 ].includes?(decl.type.id.stringify) %}
              Torrent::Util::Endian.to_network({{ decl.var.id }})
            {% else %}
              {{ decl.var.id }}
            {% end %}
          {% end %}
        end

        def ==(other_inner)
          @inner == other_inner
        end
      end
    end
  end
end
