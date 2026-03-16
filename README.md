# Whoosh

AI-first Ruby API framework inspired by FastAPI — schema validation, MCP, streaming, and OpenAPI docs out of the box.

![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.4.0-red) ![Rack](https://img.shields.io/badge/rack-3.0-blue) ![License](https://img.shields.io/badge/license-MIT-green)

## Install

```ruby
# Gemfile
gem "whoosh"
```

```sh
gem install whoosh
whoosh new my_api
```

## Quick Start

```ruby
# app.rb
require "whoosh"

app = Whoosh::App.new

app.get("/") { { message: "hello" } }

app.post("/echo", request: EchoSchema) do |req|
  { echoed: req.body[:message] }
end

run app.to_rack
```

```sh
whoosh server        # http://localhost:9292
# OpenAPI docs:      http://localhost:9292/docs
```

## Routing

### Inline

```ruby
app.get("/users/:id") do |req|
  { id: req.path_params[:id] }
end

app.post("/items", request: ItemSchema) do |req|
  { created: req.body }
end
```

### Class-based

```ruby
class UsersEndpoint < Whoosh::Endpoint
  get "/users", auth: true
  post "/users", request: CreateUserSchema

  def call(req)
    case req.method
    when "GET"  then { users: [] }
    when "POST" then [201, {}, [JSON.generate(req.body)]]
    end
  end
end

app.load_endpoints("app/endpoints")
# or register directly:
app.register_endpoint(UsersEndpoint)
```

### Groups

```ruby
app.group("/api/v1", middleware: [RateLimitMiddleware]) do
  get("/status") { { ok: true } }

  group("/admin") do
    get("/stats", auth: true) { Stats.all }
  end
end
```

## Schema Validation

```ruby
class CreateUserSchema < Whoosh::Schema
  field :name,  String,  required: true
  field :email, String,  required: true
  field :age,   Integer, min: 0, max: 150
  field :role,  String,  default: "user"
end

class AddressSchema < Whoosh::Schema
  field :street, String, required: true
  field :city,   String, required: true
end

class ProfileSchema < Whoosh::Schema
  field :bio,     String
  field :address, AddressSchema   # nested
end
```

Validation runs automatically when a route has `request:`. Errors return `422` with field-level details:

```json
{ "errors": [{ "field": "email", "message": "is missing", "value": null }] }
```

## Auth

### API Key

```ruby
app.auth do
  api_key header: "X-Api-Key", keys: {
    "sk-prod-abc123" => { tier: :premium, models: ["gpt-4"] },
    "sk-free-xyz789" => { tier: :free }
  }
end

app.get("/protected", auth: true) do |req|
  key_info = req.env["whoosh.auth"]
  { tier: key_info[:tier] }
end
```

### JWT

```ruby
app.auth do
  jwt secret: ENV["JWT_SECRET"], algorithm: :hs256, expiry: 3600
end
```

### Rate Limiting

```ruby
app.rate_limit do
  default limit: 60, period: 60

  rule "/api/completions", limit: 10, period: 60

  tier :free,    limit: 100, period: 3600
  tier :premium, limit: 5000, period: 3600
  tier :internal, unlimited: true

  on_store_failure :fail_open   # or :fail_closed
end
```

### Token Usage Tracking

```ruby
app.token_tracking do
  on_usage do |key, prompt_tokens, completion_tokens|
    UsageLog.record(key: key, prompt: prompt_tokens, completion: completion_tokens)
  end
end
```

## Streaming

### SSE

```ruby
app.get("/events") do
  stream(:sse) do |sse|
    sse.event("connected", { ts: Time.now.to_i })
    sse << { message: "hello" }
    sse.event("update", { value: 42 })
    sse.close
  end
end
```

### LLM Streaming (OpenAI-compatible)

```ruby
app.post("/chat") do |req|
  stream_llm do |s|
    llm.chat(req.body[:messages]).each_chunk do |chunk|
      s << chunk          # emits OpenAI-format delta SSE
    end
    s.finish              # sends data: [DONE]
  end
end
```

### WebSocket

```ruby
app.get("/ws") do |req|
  ws = Whoosh::Streaming::WebSocket.new(req.env)
  ws.on_message { |msg| ws.send(msg.upcase) }
  ws.rack_response
end
```

## MCP

Routes marked `mcp: true` are automatically registered as MCP tools.

```ruby
app.post("/tools/search", mcp: true, request: SearchSchema) do |req|
  Results.search(req.body[:query])
end

app.post("/tools/summarize", mcp: true, request: SummarizeSchema) do |req|
  Summarizer.run(req.body[:text])
end
```

Start the MCP server over stdio (for Claude Desktop, Cursor, etc.):

```sh
whoosh mcp                 # stdio JSON-RPC 2.0
whoosh mcp --list          # list registered tools
```

Connect an MCP client:

```ruby
app.mcp_client :python_tools, command: "python tools_server.py"

app.get("/analyze") do
  python_tools.call_tool("analyze", { input: "data" })
end
```

## Plugins

Whoosh auto-discovers AI gems from `Gemfile.lock` and exposes them as lazy accessors.

```ruby
# Gemfile
gem "ruby_llm"
gem "rag-ruby"
gem "zvec-ruby"

# app.rb — accessors available automatically after Gemfile.lock scan
app.get("/generate") do
  llm.chat("Hello")          # ruby_llm
end

app.get("/search") do |req|
  results = rag.search(req.query_params[:q])  # rag-ruby
  { results: results }
end
```

Configure or disable in `config/plugins.yml`:

```yaml
llm:
  enabled: true
  model: gpt-4o

guardrails:
  enabled: false
```

Or in code:

```ruby
app.plugin :llm, model: "gpt-4o-mini"
app.plugin :rag, enabled: false
```

Built-in mappings: `ruby_llm`, `rag-ruby`, `zvec-ruby`, `onnx-ruby`, `tokenizer-ruby`, `reranker-ruby`, `chunker-ruby`, `guardrails-ruby`, `lingua-ruby`, `ner-ruby`, `prompter-ruby`, `sequel`, and more (18 total).

## OpenAPI Docs

Auto-generated from routes and schemas. Available at `/docs` (Swagger UI) and `/openapi.json`.

```ruby
app.openapi do
  title "My AI API"
  version "1.0.0"
  description "Powers our AI features"
end

# disable if needed:
# config/app.yml → docs.enabled: false
```

## CLI Commands

```sh
whoosh new my_api [--minimal|--full]  # scaffold new project
whoosh server [-p PORT]               # start server
whoosh routes                         # list all routes
whoosh console                        # IRB with app loaded
whoosh mcp [--list]                   # MCP stdio server

whoosh generate endpoint users        # endpoint + schema + spec
whoosh generate schema CreateUser     # schema file
whoosh generate model User name:string email:string
whoosh generate migration add_index_to_users
```

## Performance

| Benchmark | Result |
|---|---|
| Simple JSON endpoint | 406K req/s |
| Schema-validated endpoint | 115K req/s |
| Router lookup (static) | 6.1M lookups/s |
| Framework overhead | ~2.5µs |

```ruby
# YJIT auto-enabled, Oj auto-detected
Whoosh::Performance.optimize!   # called automatically on server start

Whoosh::Performance.yjit_enabled?   # => true
Whoosh::Serialization::Json.engine  # => :oj or :json
```

Static routes use an O(1) hash cache. Middleware is compiled once at startup. Headers are frozen.

## Configuration

`config/app.yml` (ERB supported):

```yaml
app:
  name: My API
  env: production
  port: 9292
  host: 0.0.0.0

server:
  type: falcon
  workers: auto
  timeout: 30

logging:
  level: info      # debug | info | warn | error
  format: json     # json | text

docs:
  enabled: true

performance:
  yjit: true
  yjit_exec_mem: 64
```

Environment variable overrides:

```sh
WHOOSH_PORT=8080
WHOOSH_HOST=0.0.0.0
WHOOSH_ENV=production
WHOOSH_LOG_LEVEL=warn
WHOOSH_LOG_FORMAT=json
```

Health check:

```ruby
app.health_check(path: "/healthz") do
  probe(:database) { DB.test_connection }
  probe(:redis)    { Redis.current.ping }
end
```

## License

MIT
