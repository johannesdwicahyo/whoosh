# frozen_string_literal: true

module Whoosh
  module Serialization
    class Protobuf
      @available = nil

      def self.available?
        if @available.nil?
          @available = begin
            require "google/protobuf"
            true
          rescue LoadError
            false
          end
        end
        @available
      end

      def self.content_type
        "application/protobuf"
      end

      def self.encode(data, message_class: nil)
        ensure_available!
        raise Errors::DependencyError, "Protobuf encoding requires a message_class" unless message_class
        msg = message_class.new(data)
        message_class.encode(msg)
      end

      def self.decode(raw, message_class: nil)
        return nil if raw.nil? || raw.empty?
        ensure_available!
        raise Errors::DependencyError, "Protobuf decoding requires a message_class" unless message_class
        message_class.decode(raw)
      end

      def self.ensure_available!
        raise Errors::DependencyError, "Protobuf requires the 'google-protobuf' gem" unless available?
      end
    end
  end
end
