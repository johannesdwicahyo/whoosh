# frozen_string_literal: true

require "json"

module Whoosh
  module MCP
    class ClientUnavailable < Errors::WhooshError; end
    class TimeoutError < Errors::WhooshError; end

    class Client
      def initialize(stdin:, stdout:)
        @stdin = stdin
        @stdout = stdout
        @id_counter = 0
        @mutex = Mutex.new
        @closed = false
      end

      def call(method, **params)
        result = send_request("tools/call", { name: method, arguments: params.transform_keys(&:to_s) })
        symbolize_result(result)
      end

      def ping
        send_request("ping")
        true
      rescue
        false
      end

      def close
        @closed = true
        @stdin.close unless @stdin.closed?
        @stdout.close unless @stdout.closed?
      rescue IOError
      end

      def closed?
        @closed
      end

      private

      def send_request(method, params = nil)
        @mutex.synchronize do
          id = (@id_counter += 1)
          msg = Protocol.request(method, id: id, params: params)
          @stdin.puts(Protocol.encode(msg))
          @stdin.flush
          line = @stdout.gets
          raise ClientUnavailable, "No response from MCP server" unless line
          response = Protocol.parse(line)
          raise ClientUnavailable, "MCP error: #{response['error']['message']}" if response["error"]
          response["result"]
        end
      end

      def symbolize_result(result)
        return result unless result.is_a?(Hash)
        result.each_with_object({}) do |(k, v), h|
          key = k.is_a?(String) ? k.to_sym : k
          h[key] = case v
          when Hash then symbolize_result(v)
          when Array then v.map { |e| e.is_a?(Hash) ? symbolize_result(e) : e }
          else v
          end
        end
      end
    end
  end
end
