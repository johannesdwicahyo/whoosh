# spec/whoosh/mcp/schema_conversion_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

class MCPConvTestSchema < Whoosh::Schema
  field :message, String, required: true, desc: "The user message"
  field :temperature, Float, default: 0.7, min: 0.0, max: 2.0
end

RSpec.describe "MCP schema conversion" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  before do
    application.post "/chat", request: MCPConvTestSchema, mcp: true do |req|
      { reply: req.body[:message] }
    end
  end

  it "converts request schema to MCP tool inputSchema" do
    app
    tools = application.mcp_server.list_tools
    chat_tool = tools.find { |t| t[:name] == "POST /chat" }
    expect(chat_tool[:inputSchema][:type]).to eq("object")
    expect(chat_tool[:inputSchema][:properties][:message][:type]).to eq("string")
    expect(chat_tool[:inputSchema][:properties][:message][:description]).to eq("The user message")
    expect(chat_tool[:inputSchema][:required]).to include(:message)
  end

  it "includes field constraints" do
    app
    tools = application.mcp_server.list_tools
    chat_tool = tools.find { |t| t[:name] == "POST /chat" }
    temp = chat_tool[:inputSchema][:properties][:temperature]
    expect(temp[:minimum]).to eq(0.0)
    expect(temp[:maximum]).to eq(2.0)
    expect(temp[:default]).to eq(0.7)
  end
end
