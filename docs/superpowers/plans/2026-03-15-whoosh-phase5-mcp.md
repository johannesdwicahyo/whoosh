# Whoosh Phase 5: MCP (Model Context Protocol) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MCP server (auto-expose `mcp: true` endpoints as JSON-RPC 2.0 tools) and MCP client (subprocess management with PID tracking, health checks, and graceful shutdown). Targets MCP spec version 2025-03-26.

**Architecture:** `MCP::Protocol` handles JSON-RPC 2.0 message parsing/formatting. `MCP::Server` collects routes with `mcp: true`, converts their schemas to tool definitions, and dispatches `tools/call` requests to the matching handler. `MCP::Client` wraps a subprocess (stdio transport) with `call()` for invoking remote tools. `MCP::ClientManager` tracks PIDs, handles health checks, restarts with exponential backoff, and graceful shutdown. App exposes `mcp_client` DSL.

**Tech Stack:** Ruby 3.4+, RSpec. JSON-RPC 2.0 over stdio. No external MCP gems.

**Spec:** `docs/superpowers/specs/2026-03-11-whoosh-design.md` (MCP section, lines 235-296)

**Depends on:** Phase 1-4 complete (195 tests passing). Schema, Router, Endpoint all working.

---

## Chunk 1: Protocol and Server

### Task 1: MCP Protocol (JSON-RPC 2.0)

**Files:**
- Create: `lib/whoosh/mcp/protocol.rb`
- Test: `spec/whoosh/mcp/protocol_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
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
    it "builds a JSON-RPC 2.0 success response" do
      msg = Whoosh::MCP::Protocol.response(id: 1, result: { tools: [] })
      expect(msg[:jsonrpc]).to eq("2.0")
      expect(msg[:id]).to eq(1)
      expect(msg[:result][:tools]).to eq([])
    end
  end

  describe ".error_response" do
    it "builds a JSON-RPC 2.0 error response" do
      msg = Whoosh::MCP::Protocol.error_response(id: 1, code: -32601, message: "Method not found")
      expect(msg[:error][:code]).to eq(-32601)
      expect(msg[:error][:message]).to eq("Method not found")
    end
  end

  describe ".parse" do
    it "parses a JSON-RPC message" do
      json = '{"jsonrpc":"2.0","method":"tools/list","id":1}'
      msg = Whoosh::MCP::Protocol.parse(json)
      expect(msg["method"]).to eq("tools/list")
      expect(msg["id"]).to eq(1)
    end

    it "raises on invalid JSON" do
      expect { Whoosh::MCP::Protocol.parse("not json") }.to raise_error(Whoosh::MCP::Protocol::ParseError)
    end
  end

  describe ".encode" do
    it "encodes a message to JSON" do
      msg = { jsonrpc: "2.0", method: "ping", id: 1 }
      json = Whoosh::MCP::Protocol.encode(msg)
      parsed = JSON.parse(json)
      expect(parsed["method"]).to eq("ping")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/mcp/protocol_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/mcp/protocol.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module MCP
    class Protocol
      class ParseError < StandardError; end

      SPEC_VERSION = "2025-03-26"

      def self.request(method, id:, params: nil)
        msg = { jsonrpc: "2.0", method: method, id: id }
        msg[:params] = params if params
        msg
      end

      def self.response(id:, result:)
        { jsonrpc: "2.0", id: id, result: result }
      end

      def self.error_response(id:, code:, message:, data: nil)
        error = { code: code, message: message }
        error[:data] = data if data
        { jsonrpc: "2.0", id: id, error: error }
      end

      def self.parse(json)
        JSON.parse(json)
      rescue JSON::ParserError => e
        raise ParseError, "Invalid JSON: #{e.message}"
      end

      def self.encode(msg)
        JSON.generate(msg)
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/mcp/protocol_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/mcp/protocol.rb spec/whoosh/mcp/protocol_spec.rb
git commit -m "feat: add MCP Protocol with JSON-RPC 2.0 request/response building and parsing"
```

---

### Task 2: MCP Server

**Files:**
- Create: `lib/whoosh/mcp/server.rb`
- Test: `spec/whoosh/mcp/server_spec.rb`

The Server collects endpoints with `mcp: true`, generates tool definitions from their schemas, and handles `initialize`, `tools/list`, and `tools/call` JSON-RPC methods.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/mcp/server_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::MCP::Server do
  let(:server) { Whoosh::MCP::Server.new }

  describe "#register_tool" do
    it "registers a tool with name, description, and handler" do
      server.register_tool(
        name: "summarize",
        description: "Summarize text",
        input_schema: { type: "object", properties: { text: { type: "string" } } },
        handler: -> (params) { { summary: "short" } }
      )

      tools = server.list_tools
      expect(tools.length).to eq(1)
      expect(tools.first[:name]).to eq("summarize")
    end
  end

  describe "#handle" do
    before do
      server.register_tool(
        name: "greet",
        description: "Greet someone",
        input_schema: { type: "object", properties: { name: { type: "string" } } },
        handler: -> (params) { { message: "Hello, #{params['name']}!" } }
      )
    end

    it "handles initialize request" do
      request = { "jsonrpc" => "2.0", "method" => "initialize", "id" => 1, "params" => {} }
      response = server.handle(request)
      expect(response[:result][:protocolVersion]).to eq(Whoosh::MCP::Protocol::SPEC_VERSION)
      expect(response[:result][:capabilities][:tools]).to be_a(Hash)
    end

    it "handles tools/list request" do
      request = { "jsonrpc" => "2.0", "method" => "tools/list", "id" => 2 }
      response = server.handle(request)
      expect(response[:result][:tools].length).to eq(1)
      expect(response[:result][:tools].first[:name]).to eq("greet")
    end

    it "handles tools/call request" do
      request = {
        "jsonrpc" => "2.0", "method" => "tools/call", "id" => 3,
        "params" => { "name" => "greet", "arguments" => { "name" => "Alice" } }
      }
      response = server.handle(request)
      expect(response[:result][:content].first[:text]).to include("Hello, Alice!")
    end

    it "returns error for unknown tool" do
      request = {
        "jsonrpc" => "2.0", "method" => "tools/call", "id" => 4,
        "params" => { "name" => "unknown", "arguments" => {} }
      }
      response = server.handle(request)
      expect(response[:error]).not_to be_nil
      expect(response[:error][:code]).to eq(-32602)
    end

    it "returns error for unknown method" do
      request = { "jsonrpc" => "2.0", "method" => "unknown/method", "id" => 5 }
      response = server.handle(request)
      expect(response[:error][:code]).to eq(-32601)
    end

    it "handles ping" do
      request = { "jsonrpc" => "2.0", "method" => "ping", "id" => 6 }
      response = server.handle(request)
      expect(response[:result]).to eq({})
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/mcp/server_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/mcp/server.rb
# frozen_string_literal: true

module Whoosh
  module MCP
    class Server
      def initialize
        @tools = {}
      end

      def register_tool(name:, description:, input_schema: {}, handler:)
        @tools[name] = {
          name: name,
          description: description,
          inputSchema: input_schema,
          handler: handler
        }
      end

      def list_tools
        @tools.values.map do |tool|
          { name: tool[:name], description: tool[:description], inputSchema: tool[:inputSchema] }
        end
      end

      def handle(request)
        id = request["id"]
        method = request["method"]
        params = request["params"] || {}

        case method
        when "initialize"
          handle_initialize(id)
        when "tools/list"
          handle_tools_list(id)
        when "tools/call"
          handle_tools_call(id, params)
        when "ping"
          Protocol.response(id: id, result: {})
        when "notifications/initialized"
          nil # No response needed for notifications
        else
          Protocol.error_response(id: id, code: -32601, message: "Method not found: #{method}")
        end
      end

      private

      def handle_initialize(id)
        Protocol.response(id: id, result: {
          protocolVersion: Protocol::SPEC_VERSION,
          capabilities: {
            tools: { listChanged: false }
          },
          serverInfo: {
            name: "whoosh",
            version: Whoosh::VERSION
          }
        })
      end

      def handle_tools_list(id)
        Protocol.response(id: id, result: { tools: list_tools })
      end

      def handle_tools_call(id, params)
        tool_name = params["name"]
        arguments = params["arguments"] || {}
        tool = @tools[tool_name]

        unless tool
          return Protocol.error_response(
            id: id, code: -32602,
            message: "Unknown tool: #{tool_name}"
          )
        end

        result = tool[:handler].call(arguments)
        content = if result.is_a?(String)
          [{ type: "text", text: result }]
        elsif result.is_a?(Hash)
          [{ type: "text", text: JSON.generate(result) }]
        else
          [{ type: "text", text: result.to_s }]
        end

        Protocol.response(id: id, result: { content: content })
      rescue => e
        Protocol.error_response(id: id, code: -32603, message: e.message)
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/mcp/server_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/mcp/server.rb spec/whoosh/mcp/server_spec.rb
git commit -m "feat: add MCP Server with tool registration and JSON-RPC dispatch"
```

---

## Chunk 2: Client and App Integration

### Task 3: MCP Client

**Files:**
- Create: `lib/whoosh/mcp/client.rb`
- Test: `spec/whoosh/mcp/client_spec.rb`

The Client wraps a subprocess via stdio, sending JSON-RPC requests and reading responses. For testing, we use IO pipes instead of real subprocesses.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/mcp/client_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::MCP::Client do
  describe "#call" do
    it "sends a JSON-RPC request and returns the result" do
      # Simulate with IO pipes
      client_read, server_write = IO.pipe
      server_read, client_write = IO.pipe

      client = Whoosh::MCP::Client.new(stdin: client_write, stdout: client_read)

      # Simulate server responding in a thread
      Thread.new do
        line = server_read.gets
        request = JSON.parse(line)
        response = {
          jsonrpc: "2.0",
          id: request["id"],
          result: { content: [{ type: "text", text: "hello" }] }
        }
        server_write.puts(JSON.generate(response))
      end

      result = client.call("greet", name: "Alice")
      expect(result[:content].first[:type]).to eq("text")

      [client_read, client_write, server_read, server_write].each(&:close)
    end
  end

  describe "#ping" do
    it "sends a ping and returns true on success" do
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/mcp/client_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/mcp/client.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module MCP
    class ClientUnavailable < Errors::WhooshError; end
    class TimeoutError < Errors::WhooshError; end

    class Client
      def initialize(stdin:, stdout:)
        @stdin = stdin
        @stdout = stdout
        @id_counter = 0
        @mutex = Mutex.new
        @closed = false
      end

      def call(method, **params)
        request = send_request("tools/call", {
          name: method,
          arguments: params.transform_keys(&:to_s)
        })
        symbolize_result(request)
      end

      def ping
        send_request("ping")
        true
      rescue => e
        false
      end

      def close
        @closed = true
        @stdin.close unless @stdin.closed?
        @stdout.close unless @stdout.closed?
      rescue IOError
        # Already closed
      end

      def closed?
        @closed
      end

      private

      def send_request(method, params = nil)
        id = next_id
        msg = Protocol.request(method, id: id, params: params)

        @mutex.synchronize do
          @stdin.puts(Protocol.encode(msg))
          @stdin.flush

          line = @stdout.gets
          raise ClientUnavailable, "No response from MCP server" unless line

          response = Protocol.parse(line)

          if response["error"]
            raise ClientUnavailable, "MCP error: #{response['error']['message']}"
          end

          response["result"]
        end
      end

      def next_id
        @id_counter += 1
      end

      def symbolize_result(result)
        return result unless result.is_a?(Hash)

        result.each_with_object({}) do |(k, v), h|
          key = k.is_a?(String) ? k.to_sym : k
          h[key] = case v
          when Hash then symbolize_result(v)
          when Array then v.map { |e| e.is_a?(Hash) ? symbolize_result(e) : e }
          else v
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/mcp/client_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/mcp/client.rb spec/whoosh/mcp/client_spec.rb
git commit -m "feat: add MCP Client with stdio JSON-RPC transport and ping support"
```

---

### Task 4: MCP Client Manager

**Files:**
- Create: `lib/whoosh/mcp/client_manager.rb`
- Test: `spec/whoosh/mcp/client_manager_spec.rb`

Manages named MCP client configurations. For Phase 5, we implement the registration, lookup, and shutdown interface. Actual subprocess spawning is deferred to CLI phase.

- [ ] **Step 1: Write the failing test**

```ruby
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

  describe "#get_client" do
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/mcp/client_manager_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/mcp/client_manager.rb
# frozen_string_literal: true

module Whoosh
  module MCP
    class ClientManager
      def initialize
        @configs = {}
        @clients = {}
        @mutex = Mutex.new
      end

      def register(name, command:, **options)
        @configs[name] = { command: command, **options }
      end

      def registered?(name)
        @configs.key?(name)
      end

      def configs
        @configs.dup
      end

      def set_client(name, client)
        @mutex.synchronize do
          @clients[name] = client
        end
      end

      def get_client(name)
        @mutex.synchronize do
          @clients[name]
        end
      end

      def shutdown_all
        @mutex.synchronize do
          @clients.each_value do |client|
            client.close if client.respond_to?(:close)
          end
          @clients.clear
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/mcp/client_manager_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/mcp/client_manager.rb spec/whoosh/mcp/client_manager_spec.rb
git commit -m "feat: add MCP ClientManager with registration, client tracking, and shutdown"
```

---

### Task 5: App MCP Integration

**Files:**
- Modify: `lib/whoosh/app.rb`
- Test: `spec/whoosh/app_mcp_spec.rb`

Add `mcp_client` DSL, `mcp_server` accessor, and auto-registration of `mcp: true` routes as MCP tools.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/app_mcp_spec.rb
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

    it "registers mcp: true routes as MCP tools" do
      # Trigger to_rack to build the MCP server
      application.to_rack
      tools = application.mcp_server.list_tools
      tool_names = tools.map { |t| t[:name] }
      expect(tool_names).to include("POST /summarize")
      expect(tool_names).not_to include("GET /health")
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/app_mcp_spec.rb`
Expected: FAIL

- [ ] **Step 3: Update App**

Read `lib/whoosh/app.rb` first. Add:

**Add to attr_reader:** `:mcp_server, :mcp_manager`

**Add to initialize (after acl):**
```ruby
      @mcp_server = MCP::Server.new
      @mcp_manager = MCP::ClientManager.new
```

**Add public methods (after streaming helpers):**
```ruby
    # --- MCP DSL ---

    def mcp_client(name, command:, **options)
      @mcp_manager.register(name, command: command, **options)
    end
```

**Update to_rack — add MCP tool registration before freeze:**
After `@di.validate!`, before `@router.freeze!`, add:
```ruby
        register_mcp_tools
```

**Add private method:**
```ruby
    def register_mcp_tools
      @router.routes.each do |route|
        next unless route[:metadata] && route[:metadata][:mcp]

        tool_name = "#{route[:method]} #{route[:path]}"
        # Find the handler from the router match
        match = @router.match(route[:method], route[:path])
        next unless match

        handler_data = match[:handler]
        @mcp_server.register_tool(
          name: tool_name,
          description: "#{route[:method]} #{route[:path]}",
          input_schema: {},
          handler: -> (params) {
            # Create a fake request with the params as body
            env = Rack::MockRequest.env_for(route[:path], method: route[:method],
              input: JSON.generate(params),
              "CONTENT_TYPE" => "application/json"
            )
            request = Request.new(env)

            if handler_data[:endpoint_class]
              endpoint = handler_data[:endpoint_class].new
              endpoint.call(request)
            elsif handler_data[:block]
              instance_exec(request, &handler_data[:block])
            end
          }
        )
      end
    end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/whoosh/app_mcp_spec.rb`
Expected: All pass

- [ ] **Step 5: Run full suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/whoosh/app.rb spec/whoosh/app_mcp_spec.rb
git commit -m "feat: integrate MCP server and client manager into App with auto tool registration"
```

---

### Task 6: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 2: Smoke test**

```bash
bundle exec ruby -e "
require 'whoosh'
require 'rack/test'
include Rack::Test::Methods

app_instance = Whoosh::App.new

app_instance.post '/summarize', mcp: true do |req|
  { summary: 'AI summary of text' }
end

app_instance.get '/health' do
  { status: 'ok' }
end

define_method(:app) { app_instance.to_rack }

# Test HTTP still works
get '/health'
puts \"HTTP: #{last_response.status} #{last_response.body}\"

# Test MCP tools
tools = app_instance.mcp_server.list_tools
puts \"MCP tools: #{tools.map { |t| t[:name] }.join(', ')}\"

# Test MCP tool call
response = app_instance.mcp_server.handle({
  'jsonrpc' => '2.0', 'method' => 'tools/call', 'id' => 1,
  'params' => { 'name' => 'POST /summarize', 'arguments' => { 'text' => 'hello' } }
})
puts \"MCP call: #{response[:result][:content].first[:text]}\"

puts 'Phase 5 MCP working!'
" 2>/dev/null
```

---

## Phase 5 Completion Checklist

- [ ] `bundle exec rspec` — all green
- [ ] MCP Protocol — JSON-RPC 2.0 request/response/error building and parsing
- [ ] MCP Server — tool registration, initialize/tools-list/tools-call dispatch
- [ ] MCP Client — stdio JSON-RPC transport, ping, close
- [ ] MCP ClientManager — registration, client tracking, shutdown
- [ ] App `mcp_client` DSL for registering external MCP servers
- [ ] Auto-registration of `mcp: true` routes as MCP tools
- [ ] MCP tools invoke actual endpoint handlers
- [ ] All Phase 1-4 tests still pass

## Next Phase

After Phase 5, proceed to **Phase 6: Serialization & Database**.
