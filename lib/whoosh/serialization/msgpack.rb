# frozen_string_literal: true

module Whoosh
  module Serialization
    class Msgpack
      @available = nil

      def self.available?
        if @available.nil?
          @available = begin
            require "msgpack"
            true
          rescue LoadError
            false
          end
        end
        @available
      end

      def self.content_type
        "application/msgpack"
      end

      def self.encode(data)
        ensure_available!
        MessagePack.pack(prepare(data))
      end

      def self.decode(raw)
        return nil if raw.nil? || raw.empty?
        ensure_available!
        MessagePack.unpack(raw)
      end

      def self.prepare(obj)
        case obj
        when Hash then obj.transform_keys(&:to_s).transform_values { |v| prepare(v) }
        when Array then obj.map { |v| prepare(v) }
        when Symbol then obj.to_s
        when Time, DateTime then obj.iso8601
        when BigDecimal then obj.to_s("F")
        else obj
        end
      end

      def self.ensure_available!
        raise Errors::DependencyError, "MessagePack requires the 'msgpack' gem" unless available?
      end
    end
  end
end
