module Whoosh
  # Coercion from request input (JSON values or query strings) and
  # serialization to JSON-safe output. Each coercer returns the value or
  # raises Types::Invalid with a human message.
  module Types
    class Invalid < StandardError; end

    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
    INTEGER = /\A[+-]?\d+\z/
    DECIMAL = /\A[+-]?(\d+(\.\d*)?|\.\d+)\z/
    TRUE_VALUES = [true, "true", "1", 1, "yes", "on"].freeze
    FALSE_VALUES = [false, "false", "0", 0, "no", "off"].freeze

    # Longest string accepted when a field doesn't set max_length.
    DEFAULT_MAX_STRING = 10_000
    INTEGER_RANGE = (-(2**63)..(2**63 - 1))

    NAMES = %i[string text integer float decimal boolean date datetime time uuid email url
               array object json].freeze

    module_function

    def coerce(type, value)
      case type
      when :string, :text then string(value)
      when :integer then integer(value)
      when :float then float(value)
      when :decimal then decimal(value)
      when :boolean then boolean(value)
      when :date then date(value)
      when :datetime, :time then datetime(value)
      when :uuid then pattern(string(value).downcase, UUID, "must be a UUID")
      when :email then pattern(string(value).strip.downcase, EMAIL, "must be an email address")
      when :url then url(value)
      when :json then value
      else raise ArgumentError, "Unknown Whoosh type #{type.inspect}"
      end
    end

    def string(value)
      case value
      when String then value
      when Symbol, Numeric then value.to_s
      else raise Invalid, "must be a string"
      end
    end

    def integer(value)
      int = case value
            when Integer then value
            when String then value.strip.match?(INTEGER) ? Integer(value.strip, 10) : nil
            when Float then value == value.floor ? value.to_i : nil
            end
      raise Invalid, "must be a whole number" if int.nil?
      raise Invalid, "is out of range" unless INTEGER_RANGE.cover?(int)

      int
    end

    def float(value)
      case value
      when Float then value.finite? ? value : raise(Invalid, "must be a number")
      when Integer then value.to_f
      when String then value.strip.match?(DECIMAL) ? value.to_f : raise(Invalid, "must be a number")
      else raise Invalid, "must be a number"
      end
    end

    # Exact decimals for money. Accepts strings ("12.50") or numbers.
    def decimal(value)
      case value
      when BigDecimal then value
      when Integer then BigDecimal(value)
      when Float then value.finite? ? BigDecimal(value.to_s) : raise(Invalid, "must be a number")
      when String then value.strip.match?(DECIMAL) ? BigDecimal(value.strip) : raise(Invalid, "must be a number")
      else raise Invalid, "must be a number"
      end
    end

    def boolean(value)
      v = value.is_a?(String) ? value.strip.downcase : value
      return true if TRUE_VALUES.include?(v)
      return false if FALSE_VALUES.include?(v)

      raise Invalid, "must be true or false"
    end

    def date(value)
      return value if value.is_a?(Date) && !value.is_a?(DateTime)
      raise Invalid, "must be a date (YYYY-MM-DD)" unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(value)
    rescue Date::Error
      raise Invalid, "must be a valid date"
    end

    def datetime(value)
      return value if value.is_a?(Time)
      raise Invalid, "must be an ISO 8601 timestamp" unless value.is_a?(String)

      Time.iso8601(value)
    rescue ArgumentError
      raise Invalid, "must be an ISO 8601 timestamp"
    end

    def url(value)
      str = string(value).strip
      uri = URI.parse(str)
      raise Invalid, "must be an http(s) URL" unless %w[http https].include?(uri.scheme) && uri.host

      str
    rescue URI::InvalidURIError
      raise Invalid, "must be an http(s) URL"
    end

    def pattern(value, regex, message)
      raise Invalid, message unless value.match?(regex)

      value
    end

    # Output: turn Ruby values into JSON-safe ones.
    def dump(type, value)
      return nil if value.nil?

      case type
      when :decimal then value.is_a?(BigDecimal) ? value.to_s("F") : decimal(value).to_s("F")
      when :date then value.respond_to?(:to_date) ? value.to_date.iso8601 : value.to_s
      when :datetime, :time then value.respond_to?(:iso8601) ? value.iso8601(3) : value.to_s
      when :integer then value.is_a?(Integer) ? value : integer(value)
      when :float then value.to_f
      when :boolean then !!value
      when :string, :text, :uuid, :email, :url then value.to_s
      when :json then plain(value)
      else value
      end
    end

    # Deep-convert a value into plain JSON types (for :json fields).
    def plain(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = plain(v) }
      when Array then value.map { |v| plain(v) }
      when String, Integer, Float, true, false, nil then value
      when BigDecimal then value.to_s("F")
      when Symbol then value.to_s
      when Time, Date then value.iso8601
      else value.respond_to?(:as_json) ? value.as_json : value.to_s
      end
    end
  end
end
