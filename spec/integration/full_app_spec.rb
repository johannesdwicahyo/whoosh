# frozen_string_literal: true

require "spec_helper"
require "rack/test"

# --- Schemas used across tests ---

class IntegrationUserSchema < Whoosh::Schema
  field :name, String, required: true, desc: "User name"
  field :age,  Integer, required: false, desc: "User age"
  field :role, String, default: "user", desc: "User role"
end

# ---------------------------------------------------------------------------
# Full-app integration: one Rack app exercising every major feature
# ---------------------------------------------------------------------------

RSpec.describe "Full Whoosh App integration", type: :integration do
  include Rack::Test::Methods

  # Build the app once (before(:all) equivalent using let + shared instance)
  let(:application) do
    app = Whoosh::App.new

    # ---- Auth ----
    app.auth do
      api_key header: "X-Api-Key", keys: { "sk-test" => { role: :standard } }
    end

    # ---- Rate limiting ----
    app.rate_limit do
      default limit: 100, period: 60
      rule "/limited", limit: 2, period: 60
    end

    # ---- Access control ----
    app.access_control do
      role :standard, models: ["claude-haiku"]
    end

    # ---- OpenAPI metadata ----
    app.openapi do
      title "Test API"
      version "1.0.0"
      description "Integration test suite API"
    end

    # ---- Dependency injection ----
    app.provide(:greeting) { "Howdy" }
    app.provide(:db_url)   { "sqlite://test.db" }

    # ---- Simple GET ----
    app.get "/health" do
      { status: "ok", version: "1.0.0" }
    end

    # ---- Path params ----
    app.get "/users/:id" do |req|
      { user_id: req.params[:id] }
    end

    # ---- JSON body (string keys, no schema) ----
    app.post "/echo" do |req|
      { echoed: req.body["message"] }
    end

    # ---- Schema validation ----
    app.post "/users", request: IntegrationUserSchema do |req|
      { created: true, name: req.body[:name], role: req.body[:role] }
    end

    # ---- Auth-protected route ----
    app.get "/protected", auth: :api_key do |req|
      { authenticated: true, key: req.env["whoosh.auth"][:key] }
    end

    # ---- Rate-limited route ----
    app.get "/limited" do
      { ok: true }
    end

    # ---- SSE streaming ----
    app.get "/stream/sse" do
      stream :sse do |out|
        out.event("ping", { ts: 1 })
        out << { data: "hello" }
      end
    end

    # ---- LLM streaming ----
    app.post "/stream/llm" do |req|
      stream_llm do |out|
        out << "Hello"
        out << " World"
        out.finish
      end
    end

    # ---- Route groups ----
    app.group "/api/v1" do
      get "/items" do
        { items: %w[a b c] }
      end

      post "/items" do |req|
        { created: true, name: req.body["name"] }
      end
    end

    # ---- Dependency injection ----
    app.get "/hello/:name" do |req, greeting:|
      { message: "#{greeting}, #{req.params[:name]}!" }
    end

    # ---- MCP tool registration ----
    app.post "/summarize", mcp: true do |req|
      { summary: "short version of: #{req.body["text"]}" }
    end

    app
  end

  def app
    application.to_rack
  end

  # ---------------------------------------------------------------------------
  # Simple GET
  # ---------------------------------------------------------------------------

  describe "simple GET /health" do
    it "returns 200" do
      get "/health"
      expect(last_response.status).to eq(200)
    end

    it "returns JSON body" do
      get "/health"
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("ok")
    end

    it "sets application/json content-type" do
      get "/health"
      expect(last_response.content_type).to include("application/json")
    end
  end

  # ---------------------------------------------------------------------------
  # 404
  # ---------------------------------------------------------------------------

  describe "unknown route" do
    it "returns 404" do
      get "/does-not-exist"
      expect(last_response.status).to eq(404)
    end

    it "returns error JSON with not_found code" do
      get "/does-not-exist"
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("not_found")
    end
  end

  # ---------------------------------------------------------------------------
  # Path params
  # ---------------------------------------------------------------------------

  describe "path params GET /users/:id" do
    it "extracts :id from the URL" do
      get "/users/42"
      body = JSON.parse(last_response.body)
      expect(body["user_id"]).to eq("42")
    end

    it "works with string IDs" do
      get "/users/abc-xyz"
      body = JSON.parse(last_response.body)
      expect(body["user_id"]).to eq("abc-xyz")
    end
  end

  # ---------------------------------------------------------------------------
  # Schema validation
  # ---------------------------------------------------------------------------

  describe "schema validation POST /users" do
    context "with valid payload" do
      it "returns 200 and defaults applied" do
        post "/users", { name: "Alice" }.to_json, "CONTENT_TYPE" => "application/json"
        expect(last_response.status).to eq(200)
        body = JSON.parse(last_response.body)
        expect(body["name"]).to eq("Alice")
        expect(body["role"]).to eq("user")  # default applied
        expect(body["created"]).to be true
      end

      it "accepts optional age field" do
        post "/users", { name: "Bob", age: 30 }.to_json, "CONTENT_TYPE" => "application/json"
        expect(last_response.status).to eq(200)
      end
    end

    context "with invalid payload (missing required field)" do
      it "returns 422" do
        post "/users", {}.to_json, "CONTENT_TYPE" => "application/json"
        expect(last_response.status).to eq(422)
      end

      it "returns validation_failed error code" do
        post "/users", {}.to_json, "CONTENT_TYPE" => "application/json"
        body = JSON.parse(last_response.body)
        expect(body["error"]).to eq("validation_failed")
      end

      it "includes field errors" do
        post "/users", {}.to_json, "CONTENT_TYPE" => "application/json"
        body = JSON.parse(last_response.body)
        expect(body["details"]).not_to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # API key auth
  # ---------------------------------------------------------------------------

  describe "API key auth" do
    context "unprotected route" do
      it "allows access without API key" do
        get "/health"
        expect(last_response.status).to eq(200)
      end
    end

    context "protected route GET /protected" do
      it "allows access with valid API key" do
        get "/protected", {}, { "HTTP_X_API_KEY" => "sk-test" }
        expect(last_response.status).to eq(200)
        body = JSON.parse(last_response.body)
        expect(body["authenticated"]).to be true
        expect(body["key"]).to eq("sk-test")
      end

      it "returns 401 without API key" do
        get "/protected"
        expect(last_response.status).to eq(401)
      end

      it "returns 401 with invalid API key" do
        get "/protected", {}, { "HTTP_X_API_KEY" => "sk-invalid" }
        expect(last_response.status).to eq(401)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Rate limiting
  # ---------------------------------------------------------------------------

  describe "rate limiting GET /limited" do
    # Use a fresh app per example to reset in-memory counters
    let(:rate_app) do
      a = Whoosh::App.new
      a.rate_limit do
        default limit: 100, period: 60
        rule "/limited", limit: 2, period: 60
      end
      a.get("/limited") { { ok: true } }
      a
    end

    def app = rate_app.to_rack

    it "allows requests within the limit" do
      2.times { get "/limited" }
      expect(last_response.status).to eq(200)
    end

    it "returns 429 when limit exceeded" do
      3.times { get "/limited" }
      expect(last_response.status).to eq(429)
    end
  end

  # ---------------------------------------------------------------------------
  # SSE streaming
  # ---------------------------------------------------------------------------

  describe "SSE streaming GET /stream/sse" do
    it "returns text/event-stream content-type" do
      get "/stream/sse"
      expect(last_response.headers["content-type"]).to eq("text/event-stream")
    end

    it "includes named SSE events" do
      get "/stream/sse"
      expect(last_response.body).to include("event: ping")
    end

    it "includes data payloads" do
      get "/stream/sse"
      expect(last_response.body).to include("data:")
      expect(last_response.body).to include("hello")
    end
  end

  # ---------------------------------------------------------------------------
  # LLM streaming
  # ---------------------------------------------------------------------------

  describe "LLM streaming POST /stream/llm" do
    it "returns text/event-stream content-type" do
      post "/stream/llm"
      expect(last_response.headers["content-type"]).to eq("text/event-stream")
    end

    it "emits OpenAI-compatible delta chunks" do
      post "/stream/llm"
      data_line = last_response.body.lines.find { |l| l.start_with?("data: {") }
      expect(data_line).not_to be_nil
      chunk = JSON.parse(data_line.sub("data: ", "").strip)
      expect(chunk["choices"][0]["delta"]["content"]).to eq("Hello")
    end

    it "ends with [DONE] sentinel" do
      post "/stream/llm"
      expect(last_response.body).to include("data: [DONE]")
    end
  end

  # ---------------------------------------------------------------------------
  # Route groups
  # ---------------------------------------------------------------------------

  describe "route groups /api/v1" do
    it "GET /api/v1/items returns grouped route" do
      get "/api/v1/items"
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["items"]).to eq(%w[a b c])
    end

    it "POST /api/v1/items works in group" do
      post "/api/v1/items", { name: "widget" }.to_json, "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["created"]).to be true
    end

    it "non-grouped route is not prefixed" do
      get "/items"
      expect(last_response.status).to eq(404)
    end
  end

  # ---------------------------------------------------------------------------
  # Dependency injection
  # ---------------------------------------------------------------------------

  describe "dependency injection GET /hello/:name" do
    it "injects :greeting dependency" do
      get "/hello/Alice"
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["message"]).to eq("Howdy, Alice!")
    end
  end

  # ---------------------------------------------------------------------------
  # Security headers
  # ---------------------------------------------------------------------------

  describe "security headers" do
    it "includes x-content-type-options: nosniff" do
      get "/health"
      expect(last_response.headers["x-content-type-options"]).to eq("nosniff")
    end

    it "includes x-frame-options: DENY" do
      get "/health"
      expect(last_response.headers["x-frame-options"]).to eq("DENY")
    end
  end

  # ---------------------------------------------------------------------------
  # OpenAPI spec endpoint
  # ---------------------------------------------------------------------------

  describe "OpenAPI spec GET /openapi.json" do
    it "returns 200" do
      get "/openapi.json"
      expect(last_response.status).to eq(200)
    end

    it "returns application/json" do
      get "/openapi.json"
      expect(last_response.content_type).to include("application/json")
    end

    it "is valid OpenAPI 3.1.0" do
      get "/openapi.json"
      spec = JSON.parse(last_response.body)
      expect(spec["openapi"]).to eq("3.1.0")
    end

    it "includes configured title and version" do
      get "/openapi.json"
      spec = JSON.parse(last_response.body)
      expect(spec["info"]["title"]).to eq("Test API")
      expect(spec["info"]["version"]).to eq("1.0.0")
    end

    it "documents all registered paths" do
      get "/openapi.json"
      spec = JSON.parse(last_response.body)
      expect(spec["paths"]).to have_key("/health")
      expect(spec["paths"]).to have_key("/users/{id}")
      expect(spec["paths"]).to have_key("/users")
    end

    it "includes request schema for validated endpoints" do
      get "/openapi.json"
      spec = JSON.parse(last_response.body)
      expect(spec["paths"]["/users"]["post"]["requestBody"]).not_to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Swagger UI
  # ---------------------------------------------------------------------------

  describe "Swagger UI GET /docs" do
    it "returns 200" do
      get "/docs"
      expect(last_response.status).to eq(200)
    end

    it "serves HTML" do
      get "/docs"
      expect(last_response.content_type).to include("text/html")
    end

    it "includes swagger-ui reference" do
      get "/docs"
      expect(last_response.body).to include("swagger-ui")
    end
  end

  # ---------------------------------------------------------------------------
  # MCP tool registration
  # ---------------------------------------------------------------------------

  describe "MCP tool auto-registration" do
    # Ensure the Rack app is built (which triggers register_mcp_tools) before
    # inspecting mcp_server directly.
    before { app }

    it "registers mcp: true route as an MCP tool" do
      tools = application.mcp_server.list_tools
      names = tools.map { |t| t[:name] }
      expect(names).to include("POST /summarize")
    end

    it "auto-exposes all routes as MCP tools (opt-out with mcp: false)" do
      tools = application.mcp_server.list_tools
      names = tools.map { |t| t[:name] }
      # All user routes are auto-exposed
      expect(names).to include("GET /health")
      # Internal routes are excluded
      expect(names).not_to include("GET /metrics")
      expect(names).not_to include("GET /docs")
    end

    it "MCP tool can be invoked via the MCP server" do
      request = {
        "jsonrpc" => "2.0",
        "method"  => "tools/call",
        "id"      => 1,
        "params"  => { "name" => "POST /summarize", "arguments" => { "text" => "long article" } }
      }
      response = application.mcp_server.handle(request)
      expect(response[:result][:content].first[:text]).to include("short version")
    end
  end
end
