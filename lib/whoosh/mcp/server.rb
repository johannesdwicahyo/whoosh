# frozen_string_literal: true

require "json"

module Whoosh
  module MCP
    class Server
      def initialize
        @tools = {}
      end

      def register_tool(name:, description:, input_schema: {}, handler:)
        @tools[name] = { name: name, description: description, inputSchema: input_schema, handler: handler }
      end

      def list_tools
        @tools.values.map { |t| { name: t[:name], description: t[:description], inputSchema: t[:inputSchema] } }
      end

      def handle(request)
        id = request["id"]
        method = request["method"]
        params = request["params"] || {}

        case method
        when "initialize"
          Protocol.response(id: id, result: {
            protocolVersion: Protocol::SPEC_VERSION,
            capabilities: { tools: { listChanged: false } },
            serverInfo: { name: "whoosh", version: Whoosh::VERSION }
          })
        when "tools/list"
          Protocol.response(id: id, result: { tools: list_tools })
        when "tools/call"
          handle_tools_call(id, params)
        when "ping"
          Protocol.response(id: id, result: {})
        when "notifications/initialized"
          nil
        else
          Protocol.error_response(id: id, code: -32601, message: "Method not found: #{method}")
        end
      end

      private

      def handle_tools_call(id, params)
        tool = @tools[params["name"]]
        unless tool
          return Protocol.error_response(id: id, code: -32602, message: "Unknown tool: #{params['name']}")
        end

        result = tool[:handler].call(params["arguments"] || {})
        content = case result
        when String then [{ type: "text", text: result }]
        when Hash then [{ type: "text", text: JSON.generate(result) }]
        else [{ type: "text", text: result.to_s }]
        end

        Protocol.response(id: id, result: { content: content })
      rescue => e
        Protocol.error_response(id: id, code: -32603, message: e.message)
      end
    end
  end
end
