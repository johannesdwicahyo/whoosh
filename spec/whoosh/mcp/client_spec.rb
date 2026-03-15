# spec/whoosh/mcp/client_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::MCP::Client do
  describe "#call" do
    it "sends a JSON-RPC request and returns the result" do
      client_read, server_write = IO.pipe
      server_read, client_write = IO.pipe

      client = Whoosh::MCP::Client.new(stdin: client_write, stdout: client_read)

      Thread.new do
        line = server_read.gets
        request = JSON.parse(line)
        response = { jsonrpc: "2.0", id: request["id"],
          result: { content: [{ type: "text", text: "hello" }] } }
        server_write.puts(JSON.generate(response))
      end

      result = client.call("greet", name: "Alice")
      expect(result[:content].first[:type]).to eq("text")

      [client_read, client_write, server_read, server_write].each(&:close)
    end
  end

  describe "#ping" do
    it "returns true on success" do
      client_read, server_write = IO.pipe
      server_read, client_write = IO.pipe

      client = Whoosh::MCP::Client.new(stdin: client_write, stdout: client_read)

      Thread.new do
        line = server_read.gets
        request = JSON.parse(line)
        response = { jsonrpc: "2.0", id: request["id"], result: {} }
        server_write.puts(JSON.generate(response))
      end

      expect(client.ping).to be true
      [client_read, client_write, server_read, server_write].each(&:close)
    end
  end

  describe "#close" do
    it "closes the IO streams" do
      read_io, write_io = IO.pipe
      client = Whoosh::MCP::Client.new(stdin: write_io, stdout: read_io)
      client.close
      expect(client.closed?).to be true
    end
  end
end
