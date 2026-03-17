<p align="center">
  <img src="docs/images/whoosh-banner.png" alt="Whoosh — AI-First Ruby API Framework" width="100%">
</p>

<h1 align="center">Whoosh</h1>

<p align="center">
  <strong>AI-first Ruby API framework inspired by FastAPI</strong><br>
  Schema validation, MCP, streaming, background jobs, and OpenAPI docs — out of the box.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/ruby-%3E%3D%203.4.0-red" alt="Ruby">
  <img src="https://img.shields.io/badge/rack-3.0-blue" alt="Rack">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/tests-509%20passing-brightgreen" alt="Tests">
  <img src="https://img.shields.io/badge/overhead-2.5%C2%B5s-orange" alt="Performance">
</p>

---

## Why Whoosh?

- **AI-first** — MCP server built-in, LLM streaming, token tracking, plugin auto-discovery for 18+ AI gems
- **Fast** — 2.5µs framework overhead, 406K req/s on simple JSON, YJIT + Oj auto-enabled
- **Batteries included** — Auth, rate limiting, caching, background jobs, file uploads, pagination, metrics
- **Zero config to start** — `whoosh new myapp && cd myapp && whoosh s`
- **OpenAPI 3.1** — Swagger UI + ReDoc auto-generated from your routes and schemas

## Install

```sh
gem install whoosh
whoosh new my_api
cd my_api
whoosh s
```

Open http://localhost:9292/docs for Swagger UI.

## Quick Start

```ruby
# app.rb
require "whoosh"

app = Whoosh::App.new

app.get "/health" do
  { status: "ok", version: Whoosh::VERSION }
end

app.post "/chat", request: ChatRequest, mcp: true do |req|
  stream_llm do |out|
    llm.chat(req.body[:message]).each_chunk { |c| out << c }
    out.finish
  end
end
```

```sh
whoosh s              # Start server
whoosh s --reload     # Auto-reload on file changes
whoosh s -p 3000      # Custom port
```

## Features

### Routing

```ruby
# Inline
app.get("/users/:id") { |req| { id: req.params[:id] } }

# Class-based
class ChatEndpoint < Whoosh::Endpoint
  post "/chat", request: ChatRequest, mcp: true

  def call(req)
    { reply: "Hello!" }
  end
end
app.load_endpoints("endpoints/")

# Groups with shared middleware
app.group "/api/v1", mcp: true do
  get("/status") { { ok: true } }
  post("/analyze", auth: :api_key) { |req| analyze(req) }
end
```

### Schema Validation

```ruby
class CreateUserRequest < Whoosh::Schema
  field :name,  String,  required: true, desc: "User name"
  field :email, String,  required: true, desc: "Email address"
  field :age,   Integer, min: 0, max: 150
  field :role,  String,  default: "user"
end

# Returns 422 with field-level errors on invalid input
app.post "/users", request: CreateUserRequest do |req|
  { name: req.body[:name], created: true }
end
```

### Authentication & Security

```ruby
app.auth do
  api_key header: "X-Api-Key", keys: {
    "sk-prod-123" => { role: :premium },
    "sk-free-456" => { role: :free }
  }
  jwt secret: ENV["JWT_SECRET"], algorithm: :hs256
end

app.rate_limit do
  default limit: 60, period: 60
  rule "/chat", limit: 10, period: 60
  tier :free,    limit: 100,  period: 3600
  tier :premium, limit: 5000, period: 3600
  on_store_failure :fail_open
end

app.access_control do
  role :free,    models: ["claude-haiku"]
  role :premium, models: ["claude-haiku", "claude-sonnet", "claude-opus"]
end
```

### LLM Streaming (OpenAI-compatible)

```ruby
app.post "/chat/stream", auth: :api_key do |req|
  stream_llm do |out|
    # True chunked streaming via SizedQueue — tokens flow in real-time
    out << "Hello "
    out << "World!"
    out.finish  # sends data: [DONE]
  end
end

# SSE events
app.get "/events" do
  stream :sse do |out|
    out.event("status", { connected: true })
    out << { data: "hello" }
  end
end
```

### MCP (Model Context Protocol)

```ruby
# Any route with mcp: true becomes an MCP tool automatically
app.post "/summarize", mcp: true, request: SummarizeRequest do |req|
  { summary: llm.summarize(req.body[:text]) }
end

# Groups propagate mcp: true to all child routes
app.group "/tools", mcp: true do
  post("/translate") { |req| { result: translate(req.body[:text]) } }
  post("/analyze")   { |req| { result: analyze(req.body[:text]) } }
end
```

```sh
whoosh mcp              # stdio transport (Claude Desktop, Cursor)
whoosh mcp --list       # list registered MCP tools
```

### Background Jobs

```ruby
class AnalyzeJob < Whoosh::Job
  inject :db, :llm  # DI injection

  def perform(document_id:)
    doc = db[:documents].where(id: document_id).first
    result = llm.complete("Analyze: #{doc[:text]}")
    db[:documents].where(id: document_id).update(analysis: result)
    { analyzed: true }
  end
end

# Fire and forget
app.post "/analyze" do |req|
  job_id = AnalyzeJob.perform_async(document_id: req.body["id"])
  { job_id: job_id }
end

# Check status
app.get "/jobs/:id" do |req|
  job = Whoosh::Jobs.find(req.params[:id])
  { status: job[:status], result: job[:result] }
end
```

```sh
whoosh worker           # dedicated worker process
whoosh worker -c 4      # 4 threads
```

### File Upload

```ruby
app.post "/upload" do |req|
  file = req.files["document"]

  file.filename      # => "report.pdf"
  file.content_type  # => "application/pdf"
  file.size          # => 245760
  file.read_text     # => UTF-8 string (for RAG)
  file.to_base64     # => base64 (for vision APIs)
  file.validate!(types: ["application/pdf"], max_size: 10_000_000)

  path = file.save("documents")
  { path: path }
end
```

### Cache

```ruby
app.get "/users/:id" do |req, cache:|
  cache.fetch("user:#{req.params[:id]}", ttl: 60) do
    db[:users].where(id: req.params[:id]).first
  end
end
```

### Pagination

```ruby
# Offset-based
app.get "/users" do |req|
  paginate(db[:users].order(:id),
    page: req.query_params["page"], per_page: 20)
end

# Cursor-based (recommended for large datasets)
app.get "/messages" do |req|
  paginate_cursor(db[:messages].order(:id),
    cursor: req.query_params["cursor"], limit: 20)
end
```

### Plugins (18 AI Gems Auto-Discovered)

```ruby
# Just add gems to Gemfile — they're auto-discovered from Gemfile.lock
gem "ruby_llm"
gem "lingua-ruby"
gem "ner-ruby"
gem "guardrails-ruby"

# Available as bare method calls in endpoints:
app.post "/analyze" do |req|
  lang     = lingua.detect(req.body["text"])
  entities = ner.recognize(req.body["text"])
  { language: lang, entities: entities }
end
```

### HTTP Client

```ruby
app.post "/proxy" do |req, http:|
  result = http.post("https://api.example.com/analyze",
    json: req.body,
    headers: { "Authorization" => "Bearer #{ENV["API_KEY"]}" },
    timeout: 30
  )
  result.json  # parsed response
end
```

### Prometheus Metrics

Auto-tracked at `/metrics`:

```
whoosh_requests_total{method="GET",path="/health",status="200"} 1234
whoosh_request_duration_seconds_sum{path="/health"} 45.23
whoosh_request_duration_seconds_count{path="/health"} 1234
```

### OpenAPI & Docs

```ruby
app.openapi do
  title "My AI API"
  version "1.0.0"
end

app.docs enabled: true, redoc: true
```

- `/docs` — Swagger UI
- `/redoc` — ReDoc
- `/openapi.json` — Machine-readable spec

### Health Checks

```ruby
app.health_check do
  probe(:database) { db.test_connection }
  probe(:cache)    { cache.get("ping") || true }
end
# GET /healthz → { "status": "ok", "checks": { "database": "ok" } }
```

## CLI

```sh
whoosh new my_api             # scaffold project (with Dockerfile)
whoosh s                      # start server (like rails s)
whoosh s --reload             # hot reload on file changes
whoosh routes                 # list all routes
whoosh console                # IRB with app loaded
whoosh worker                 # background job worker
whoosh mcp                    # MCP stdio server

whoosh generate endpoint chat       # endpoint + schema + test
whoosh generate schema User         # schema file
whoosh generate model User name:string email:string
whoosh generate migration add_email_to_users
whoosh generate plugin my_tool      # plugin boilerplate
whoosh generate proto ChatRequest   # .proto file

whoosh db migrate             # run migrations
whoosh db rollback            # rollback
whoosh db status              # migration status
```

## Performance

### HTTP Benchmark: `GET /health → {"status":"ok"}`

> Apple Silicon arm64, 12 cores. [Full benchmark suite](benchmarks/comparison/)

**Single process** (fair 1:1 comparison):

| Framework | Language | Server | Req/sec |
|-----------|----------|--------|---------|
| Fastify | Node.js 22 | built-in | 69,200 |
| **Whoosh** | Ruby 3.4 +YJIT | **Falcon** | **24,400** |
| **Whoosh** | Ruby 3.4 +YJIT | Puma (5 threads) | **15,500** |
| FastAPI | Python 3.13 | uvicorn | 8,900 |
| Sinatra | Ruby 3.4 | Puma (5 threads) | 7,100 |
| PHP (raw) | PHP 8.5 | built-in | 2,000 |

> Whoosh + Falcon is **2.7x faster** than FastAPI single-core. Whoosh + Puma is **1.7x faster** than FastAPI. Use Falcon (recommended) for best performance.

**Multi-worker** (production deployment):

| Framework | Language | Server | Req/sec |
|-----------|----------|--------|---------|
| **Whoosh** | Ruby 3.4 +YJIT | **Falcon (4 workers)** | **87,400** |
| Fastify | Node.js 22 | built-in (single thread) | 69,200 |
| **Whoosh** | Ruby 3.4 +YJIT | Puma (4w×4t) | **52,500** |
| Roda | Ruby 3.4 | Puma (4w×4t) | 14,700 |

> **Note:** Fastify is single-threaded by design (Node.js event loop). It can scale via `cluster` module but was not tested in that mode. Whoosh + Falcon with 4 workers uses 4 cores.

### Real-World Benchmark: `GET /users/:id` from PostgreSQL (1000 rows)

**Single process:**

| Framework | Language | Req/sec |
|-----------|----------|---------|
| Fastify + pg | Node.js 22 | 36,900 |
| **Whoosh + Falcon (fiber PG pool)** | Ruby 3.4 +YJIT | **13,400** |
| **Whoosh + Puma (Sequel)** | Ruby 3.4 +YJIT | **8,600** |
| Roda + Puma | Ruby 3.4 | 6,700 |
| Sinatra + Puma | Ruby 3.4 | 4,400 |
| FastAPI + uvicorn | Python 3.13 | 2,400 |

**Multi-worker (PostgreSQL):**

| Framework | Language | Req/sec |
|-----------|----------|---------|
| **Whoosh + Falcon (4 workers, fiber PG pool)** | Ruby 3.4 +YJIT | **45,900** |
| Fastify (single thread) | Node.js 22 | 36,900 |

> Whoosh + Falcon with fiber-aware PG pool is **5.6x faster** than FastAPI. Multi-worker Falcon **beats Fastify by 24%** on real PostgreSQL workloads.

### Micro-benchmarks

| Component | Throughput |
|-----------|-----------|
| Router lookup (static, cached) | **6.1M ops/s** |
| JSON encode (Oj) | **5.4M ops/s** |
| Framework overhead | **~2.5µs per request** |

Optimizations: YJIT auto-enabled, Oj JSON auto-detected, O(1) static route cache, compiled middleware chain, pre-frozen headers.

## Configuration

```yaml
# config/app.yml
app:
  name: My API
  port: 9292

database:
  url: <%= ENV.fetch("DATABASE_URL", "sqlite://db/dev.sqlite3") %>
  max_connections: 10

cache:
  store: memory    # memory | redis
  default_ttl: 300

jobs:
  backend: memory  # memory | database | redis
  workers: 2

logging:
  level: info
  format: json

docs:
  enabled: true
```

`.env` files loaded automatically (dotenv-compatible).

## Testing

```ruby
require "whoosh/test"

RSpec.describe "My API" do
  include Whoosh::Test

  def app = MyApp.to_rack

  it "creates a user" do
    post_json "/users", { name: "Alice", email: "a@b.com" }
    assert_response 200
    assert_json(name: "Alice")
  end

  it "requires auth" do
    get "/protected"
    assert_response 401
  end

  it "works with auth" do
    get_with_auth "/protected", key: "sk-test"
    assert_response 200
  end
end
```

## License

MIT — see [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
