# spec/whoosh/mcp/transport/stdio_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::MCP::Transport::Stdio do
  let(:server) { Whoosh::MCP::Server.new }

  before do
    server.register_tool(name: "echo", description: "Echo", handler: -> (p) { { echo: p["text"] } })
  end

  it "processes JSON-RPC over stdio" do
    input = StringIO.new(JSON.generate({ jsonrpc: "2.0", method: "ping", id: 1 }) + "\n")
    output = StringIO.new

    transport = Whoosh::MCP::Transport::Stdio.new(server, input: input, output: output)
    transport.run

    output.rewind
    response = JSON.parse(output.read.strip)
    expect(response["result"]).to eq({})
  end

  it "handles parse errors" do
    input = StringIO.new("not json\n")
    output = StringIO.new

    transport = Whoosh::MCP::Transport::Stdio.new(server, input: input, output: output)
    transport.run

    output.rewind
    response = JSON.parse(output.read.strip)
    expect(response["error"]["code"]).to eq(-32700)
  end
end
