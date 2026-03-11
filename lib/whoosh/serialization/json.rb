# frozen_string_literal: true

require "json"
require "bigdecimal"

module Whoosh
  module Serialization
    class Json
      def self.encode(data)
        JSON.generate(prepare(data))
      end

      def self.decode(raw)
        return nil if raw.nil? || raw.empty?

        JSON.parse(raw)
      end

      def self.content_type
        "application/json"
      end

      def self.prepare(obj)
        case obj
        when Hash
          obj.transform_values { |v| prepare(v) }
        when Array
          obj.map { |v| prepare(v) }
        when Time, DateTime
          obj.iso8601
        when BigDecimal
          obj.to_s("F")
        else
          obj
        end
      end
    end
  end
end
