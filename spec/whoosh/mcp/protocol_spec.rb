# spec/whoosh/mcp/protocol_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::MCP::Protocol do
  describe ".request" do
    it "builds a JSON-RPC 2.0 request" do
      msg = Whoosh::MCP::Protocol.request("tools/list", id: 1)
      expect(msg[:jsonrpc]).to eq("2.0")
      expect(msg[:method]).to eq("tools/list")
      expect(msg[:id]).to eq(1)
    end

    it "includes params when provided" do
      msg = Whoosh::MCP::Protocol.request("tools/call", id: 2, params: { name: "summarize" })
      expect(msg[:params][:name]).to eq("summarize")
    end
  end

  describe ".response" do
    it "builds a success response" do
      msg = Whoosh::MCP::Protocol.response(id: 1, result: { tools: [] })
      expect(msg[:jsonrpc]).to eq("2.0")
      expect(msg[:id]).to eq(1)
      expect(msg[:result][:tools]).to eq([])
    end
  end

  describe ".error_response" do
    it "builds an error response" do
      msg = Whoosh::MCP::Protocol.error_response(id: 1, code: -32601, message: "Method not found")
      expect(msg[:error][:code]).to eq(-32601)
    end
  end

  describe ".parse" do
    it "parses JSON-RPC message" do
      msg = Whoosh::MCP::Protocol.parse('{"jsonrpc":"2.0","method":"tools/list","id":1}')
      expect(msg["method"]).to eq("tools/list")
    end

    it "raises on invalid JSON" do
      expect { Whoosh::MCP::Protocol.parse("not json") }.to raise_error(Whoosh::MCP::Protocol::ParseError)
    end
  end

  describe ".encode" do
    it "encodes to JSON" do
      json = Whoosh::MCP::Protocol.encode({ jsonrpc: "2.0", method: "ping", id: 1 })
      expect(JSON.parse(json)["method"]).to eq("ping")
    end
  end
end
