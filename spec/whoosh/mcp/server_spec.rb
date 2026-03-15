# spec/whoosh/mcp/server_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::MCP::Server do
  let(:server) { Whoosh::MCP::Server.new }

  describe "#register_tool" do
    it "registers a tool" do
      server.register_tool(name: "summarize", description: "Summarize text",
        input_schema: {}, handler: -> (params) { { summary: "short" } })
      expect(server.list_tools.length).to eq(1)
      expect(server.list_tools.first[:name]).to eq("summarize")
    end
  end

  describe "#handle" do
    before do
      server.register_tool(name: "greet", description: "Greet someone",
        input_schema: {}, handler: -> (params) { { message: "Hello, #{params['name']}!" } })
    end

    it "handles initialize" do
      response = server.handle({ "jsonrpc" => "2.0", "method" => "initialize", "id" => 1, "params" => {} })
      expect(response[:result][:protocolVersion]).to eq(Whoosh::MCP::Protocol::SPEC_VERSION)
    end

    it "handles tools/list" do
      response = server.handle({ "jsonrpc" => "2.0", "method" => "tools/list", "id" => 2 })
      expect(response[:result][:tools].length).to eq(1)
    end

    it "handles tools/call" do
      response = server.handle({ "jsonrpc" => "2.0", "method" => "tools/call", "id" => 3,
        "params" => { "name" => "greet", "arguments" => { "name" => "Alice" } } })
      expect(response[:result][:content].first[:text]).to include("Hello, Alice!")
    end

    it "returns error for unknown tool" do
      response = server.handle({ "jsonrpc" => "2.0", "method" => "tools/call", "id" => 4,
        "params" => { "name" => "unknown", "arguments" => {} } })
      expect(response[:error][:code]).to eq(-32602)
    end

    it "returns error for unknown method" do
      response = server.handle({ "jsonrpc" => "2.0", "method" => "unknown", "id" => 5 })
      expect(response[:error][:code]).to eq(-32601)
    end

    it "handles ping" do
      response = server.handle({ "jsonrpc" => "2.0", "method" => "ping", "id" => 6 })
      expect(response[:result]).to eq({})
    end
  end
end
