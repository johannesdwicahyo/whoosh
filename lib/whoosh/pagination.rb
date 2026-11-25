module Whoosh
  # Pagination without COUNT(*).
  #
  # :cursor (default) - keyset pagination on a unique, ordered column.
  #   Query: ?limit=25&cursor=<opaque>. Stable under inserts and fast at any depth.
  # :offset           - ?limit=25&page=2, for small tables and admin-style UIs.
  #
  # Works with Active Record relations and plain arrays.
  class Pagination
    Page = Struct.new(:records, :meta)

    attr_reader :style, :by, :order

    def initialize(style = :cursor, by: :id, order: :asc)
      raise DefinitionError, "paginate: style must be :cursor or :offset" unless %i[cursor offset].include?(style)
      raise DefinitionError, "paginate: order must be :asc or :desc" unless %i[asc desc].include?(order)

      @style = style
      @by = by.to_sym
      @order = order
    end

    def query_fields
      style == :cursor ? %w[limit cursor] : %w[limit page]
    end

    def call(collection, query, config)
      limit = parse_limit(query["limit"], config)
      style == :cursor ? cursor_page(collection, query["cursor"], limit) : offset_page(collection, query["page"], limit)
    end

    private

    def parse_limit(value, config)
      return config.default_page_size if value.nil? || value == ""

      limit = Types.integer(value)
      raise Types::Invalid, "must be between 1 and #{config.max_page_size}" unless limit.between?(1, config.max_page_size)

      limit
    rescue Types::Invalid => e
      raise ValidationError.new({ "limit" => [e.message] })
    end

    def cursor_page(collection, cursor, limit)
      after = decode_cursor(cursor)
      rows =
        if relation?(collection)
          rel = collection.reorder(by => order)
          if after
            column = collection.klass.arel_table[by]
            rel = rel.where(order == :asc ? column.gt(after) : column.lt(after))
          end
          rel.limit(limit + 1).to_a
        else
          list = Array(collection).sort_by { |r| value_of(r) }
          list.reverse! if order == :desc
          list = list.select { |r| order == :asc ? value_of(r) > after : value_of(r) < after } if after
          list.first(limit + 1)
        end

      more = rows.size > limit
      rows = rows.first(limit)
      next_cursor = more && rows.any? ? encode_cursor(value_of(rows.last)) : nil
      Page.new(rows, { "limit" => limit, "next_cursor" => next_cursor })
    end

    def offset_page(collection, page, limit)
      page = page.nil? || page == "" ? 1 : Types.integer(page)
      raise Types::Invalid, "must be 1 or more" if page < 1 || page > 10_000

      offset = (page - 1) * limit
      rows = if relation?(collection) then collection.offset(offset).limit(limit + 1).to_a
             else Array(collection)[offset, limit + 1] || []
             end
      more = rows.size > limit
      Page.new(rows.first(limit), { "limit" => limit, "page" => page, "next_page" => more ? page + 1 : nil })
    rescue Types::Invalid => e
      raise ValidationError.new({ "page" => [e.message] })
    end

    def relation?(collection)
      collection.respond_to?(:klass) && collection.respond_to?(:reorder) && collection.respond_to?(:where)
    end

    def value_of(record)
      record.is_a?(Hash) ? (record[by] || record[by.to_s]) : record.public_send(by)
    end

    def encode_cursor(value)
      # Times keep their full precision; JSON alone would cut them to whole seconds.
      payload = value.is_a?(Time) ? ["t", value.iso8601(9)] : [value]
      [::JSON.generate(payload)].pack("m0").tr("+/", "-_").delete("=") # urlsafe base64; the base64 gem left stdlib in 3.4
    end

    def decode_cursor(cursor)
      return nil if cursor.nil? || cursor == ""
      raise ArgumentError if cursor.length > 512

      payload = ::JSON.parse(cursor.tr("-_", "+/").unpack1("m"))
      value = payload.length == 2 && payload[0] == "t" ? Time.iso8601(payload[1]) : payload.first
      raise ArgumentError unless value.is_a?(Integer) || value.is_a?(String) || value.is_a?(Time)

      value
    rescue ArgumentError, TypeError, ::JSON::ParserError, NoMethodError
      raise ValidationError.new({ "cursor" => ["is invalid"] })
    end
  end
end
