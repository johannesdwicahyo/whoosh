# spec/whoosh/mcp/client_manager_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::MCP::ClientManager do
  let(:manager) { Whoosh::MCP::ClientManager.new }

  describe "#register" do
    it "registers a named client configuration" do
      manager.register(:filesystem, command: "npx @mcp/server-filesystem /tmp")
      expect(manager.registered?(:filesystem)).to be true
    end
  end

  describe "#configs" do
    it "returns all registered configurations" do
      manager.register(:fs, command: "cmd1")
      manager.register(:gh, command: "cmd2")
      expect(manager.configs.keys).to contain_exactly(:fs, :gh)
    end
  end

  describe "#shutdown_all" do
    it "closes all active clients" do
      read_io, write_io = IO.pipe
      client = Whoosh::MCP::Client.new(stdin: write_io, stdout: read_io)
      manager.set_client(:test, client)
      manager.shutdown_all
      expect(client.closed?).to be true
    end
  end

  describe "#get_client / #set_client" do
    it "returns nil for unconnected client" do
      manager.register(:fs, command: "cmd")
      expect(manager.get_client(:fs)).to be_nil
    end

    it "returns client after set_client" do
      client = double("client")
      manager.set_client(:fs, client)
      expect(manager.get_client(:fs)).to eq(client)
    end
  end
end
