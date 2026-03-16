# spec/whoosh/mcp/transport/sse_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::MCP::Transport::SSE do
  let(:server) { Whoosh::MCP::Server.new }
  let(:transport) { Whoosh::MCP::Transport::SSE.new(server) }

  before do
    server.register_tool(name: "echo", description: "Echo", handler: -> (p) { { echo: p["text"] } })
  end

  describe "#handle_request" do
    it "returns SSE response for tools/list" do
      body = JSON.generate({ jsonrpc: "2.0", method: "tools/list", id: 1 })
      status, headers, response = transport.handle_request(body)
      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("text/event-stream")
      json_line = response.first.lines.find { |l| l.start_with?("data:") }
      parsed = JSON.parse(json_line.sub("data: ", "").strip)
      expect(parsed["result"]["tools"].first["name"]).to eq("echo")
    end

    it "handles tools/call" do
      body = JSON.generate({ jsonrpc: "2.0", method: "tools/call", id: 2, params: { name: "echo", arguments: { text: "hi" } } })
      _, _, response = transport.handle_request(body)
      json_line = response.first.lines.find { |l| l.start_with?("data:") }
      parsed = JSON.parse(json_line.sub("data: ", "").strip)
      expect(parsed["result"]["content"].first["text"]).to include("hi")
    end

    it "returns error for invalid JSON" do
      _, _, response = transport.handle_request("bad")
      json_line = response.first.lines.find { |l| l.start_with?("data:") }
      parsed = JSON.parse(json_line.sub("data: ", "").strip)
      expect(parsed["error"]).not_to be_nil
    end
  end
end
