# spec/whoosh/mcp/client_spawn_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MCP client spawning" do
  let(:manager) { Whoosh::MCP::ClientManager.new }
  let(:echo_cmd) { %(ruby -e "require 'json'; STDOUT.sync=true; STDIN.each_line{|l| r=JSON.parse(l); STDOUT.puts(JSON.generate({jsonrpc:'2.0',id:r['id'],result:{}}))}") }

  after { manager.shutdown_all }

  describe "#spawn_client" do
    it "spawns and returns a working client" do
      manager.register(:echo, command: echo_cmd)
      client = manager.spawn_client(:echo)
      expect(client).to be_a(Whoosh::MCP::Client)
      expect(client.ping).to be true
    end

    it "tracks PIDs" do
      manager.register(:echo, command: echo_cmd)
      manager.spawn_client(:echo)
      expect(manager.pids).to have_key(:echo)
      expect(manager.pids[:echo]).to be_a(Integer)
    end

    it "raises for unregistered client" do
      expect { manager.spawn_client(:unknown) }.to raise_error(Whoosh::Errors::DependencyError)
    end
  end
end
