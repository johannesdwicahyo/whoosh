# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App MCP integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "#mcp_client" do
    it "registers MCP client configurations" do
      application.mcp_client :filesystem, command: "npx @mcp/server-filesystem /tmp"
      expect(application.mcp_manager.registered?(:filesystem)).to be true
    end
  end

  describe "mcp_server" do
    it "exposes an MCP server instance" do
      expect(application.mcp_server).to be_a(Whoosh::MCP::Server)
    end
  end

  describe "auto-registering mcp: true routes" do
    before do
      application.post "/summarize", mcp: true do |req|
        { summary: "short version" }
      end

      application.get "/health" do
        { status: "ok" }
      end
    end

    it "auto-exposes all routes as MCP tools" do
      application.to_rack
      tools = application.mcp_server.list_tools
      tool_names = tools.map { |t| t[:name] }
      expect(tool_names).to include("POST /summarize")
      expect(tool_names).to include("GET /health")
    end

    it "excludes routes with mcp: false" do
      application.get "/internal", mcp: false do
        { internal: true }
      end
      application.to_rack
      tool_names = application.mcp_server.list_tools.map { |t| t[:name] }
      expect(tool_names).not_to include("GET /internal")
    end

    it "MCP tools invoke the endpoint handler" do
      application.to_rack
      request = {
        "jsonrpc" => "2.0", "method" => "tools/call", "id" => 1,
        "params" => { "name" => "POST /summarize", "arguments" => {} }
      }
      response = application.mcp_server.handle(request)
      expect(response[:result][:content].first[:text]).to include("short version")
    end
  end
end
