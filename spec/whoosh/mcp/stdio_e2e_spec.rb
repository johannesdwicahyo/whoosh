# spec/whoosh/mcp/stdio_e2e_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "open3"

RSpec.describe "MCP stdio end-to-end" do
  it "communicates over stdio with a subprocess MCP server" do
    server_script = <<~'RUBY'
      require "json"
      STDOUT.sync = true
      STDIN.each_line do |line|
        req = JSON.parse(line)
        case req["method"]
        when "ping"
          STDOUT.puts JSON.generate({ jsonrpc: "2.0", id: req["id"], result: {} })
        when "tools/call"
          name = req.dig("params", "arguments", "name") || "World"
          STDOUT.puts JSON.generate({ jsonrpc: "2.0", id: req["id"], result: { content: [{ type: "text", text: "Hello, #{name}!" }] } })
        else
          STDOUT.puts JSON.generate({ jsonrpc: "2.0", id: req["id"], error: { code: -32601, message: "Unknown" } })
        end
      end
    RUBY

    stdin, stdout, stderr, wait_thr = Open3.popen3("ruby", "-e", server_script)
    client = Whoosh::MCP::Client.new(stdin: stdin, stdout: stdout)

    expect(client.ping).to be true

    result = client.call("greet", name: "Alice")
    expect(result[:content].first[:text]).to eq("Hello, Alice!")

    client.close
    stderr.close
    Process.kill("TERM", wait_thr.pid) rescue nil
    wait_thr.join(2)
  end
end
