# frozen_string_literal: true

require "json"

module Whoosh
  module MCP
    class Protocol
      class ParseError < StandardError; end

      SPEC_VERSION = "2025-03-26"

      def self.request(method, id:, params: nil)
        msg = { jsonrpc: "2.0", method: method, id: id }
        msg[:params] = params if params
        msg
      end

      def self.response(id:, result:)
        { jsonrpc: "2.0", id: id, result: result }
      end

      def self.error_response(id:, code:, message:, data: nil)
        error = { code: code, message: message }
        error[:data] = data if data
        { jsonrpc: "2.0", id: id, error: error }
      end

      def self.parse(json)
        JSON.parse(json)
      rescue JSON::ParserError => e
        raise ParseError, "Invalid JSON: #{e.message}"
      end

      def self.encode(msg)
        JSON.generate(msg)
      end
    end
  end
end
