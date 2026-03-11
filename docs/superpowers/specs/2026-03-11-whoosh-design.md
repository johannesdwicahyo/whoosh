# Whoosh — AI-First Ruby API Framework

**Date:** 2026-03-11
**Status:** Approved
**Gem name:** `whoosh`
**Ruby:** 3.4+ (Ruby 4 ready)

## Overview

Whoosh is an AI-first Ruby web API framework inspired by FastAPI. It provides a modern, fast, and secure foundation for building AI-powered APIs with built-in MCP support, automatic OpenAPI documentation, and seamless integration with a 15+ gem NLP/AI ecosystem.

Whoosh is a smart monolith with lazy loading — one gem install gives you everything, but modules only load when used. Lazy loading uses `autoload` (thread-safe in Ruby 3.4+ MRI and fiber-safe for Falcon). Four hard dependencies: rack, dry-schema, dry-types, thor.

## What Makes It Different

1. No other Ruby framework is AI-first
2. MCP (Model Context Protocol) built-in, not bolted on — both server and client
3. 15+ NLP/AI gems auto-discovered as plugins from Gemfile
4. LLM streaming with real-time guardrails checking
5. AI-specific auth: token usage tracking, per-key model access control, rate limit tiers
6. Auto-generated OpenAPI 3.1 docs with Swagger UI — zero extra work
7. One gem install, zero config to start

## Architecture

```
+-----------------------------------------------------+
|                    CLI (Thor)                         |
|  new - server - routes - generate - console - mcp    |
+------------------------+----------------------------+
                         |
+------------------------v----------------------------+
|                   Application                        |
|  +---------+ +----------+ +-----------+             |
|  | Router  | | Schema   | | Plugin    |             |
|  |         | | (dry-rb) | | Registry  |             |
|  +----+----+ +----+-----+ +-----+-----+             |
|       |           |             |                    |
|  +----v-----------v-------------v-----+              |
|  |         Middleware Stack            |              |
|  |  CORS - Auth - RateLimit - Logger  |              |
|  +-----------------+------------------+              |
|                    |                                 |
|  +-----------------v------------------+              |
|  |          Rack Interface            |              |
|  |    (Falcon default, Puma compat)   |              |
|  +------------------------------------+              |
|                                                      |
|  -- Lazy-loaded modules ----------------------------+|
|  | MCP Server | MCP Client | Streaming | Auth |     ||
|  | OpenAPI    | WebSocket  | SSE       |      |     ||
+-----------------------------------------------------+
```

### Core Components

- **Router** — Trie-based for fast route matching (O(k) where k = number of path segments, effectively constant for typical API paths). Supports path params, query params, constraints.
- **Schema** — Wraps dry-schema + dry-types. Users declare fields with a simple DSL, never touch dry-rb directly unless they want to. Powers validation, serialization, and OpenAPI generation.
- **Plugin Registry** — Scans Gemfile.lock for recognized gems at boot. Registers lazy-loaded accessors. Zero cost if never called. Thread-safe and fiber-safe — uses `Mutex` on first initialization, accessor is a direct reference thereafter.
- **Middleware Stack** — Standard Rack middleware chain. AI-specific middleware (guardrails, token tracking) included.
- **Rack Interface** — Standard `call(env)` contract. Works with Falcon (async, recommended), Puma (threaded), or any Rack server.

## Routing & Endpoint DSL

Whoosh supports two routing styles: inline blocks on the `app` object, and class-based endpoints auto-loaded from the `endpoints/` directory.

### Inline style (small apps, prototyping)

```ruby
require "whoosh"

app = Whoosh::App.new

# Simple endpoint
app.get "/health" do
  { status: "ok" }
end

# Schema-validated endpoint
app.post "/chat", request: ChatRequest, response: ChatResponse do |req|
  result = llm.complete(req.message)
  { reply: result.text, tokens: result.usage }
end

# Grouped routes with shared middleware
app.group "/api/v1", middleware: [:auth, :rate_limit] do
  get "/models" do
    { models: registry.available_models }
  end

  post "/completions", request: CompletionRequest do |req|
    stream do |out|
      llm.stream(req.prompt) { |chunk| out << chunk }
    end
  end
end

# Dependency injection
app.provide(:db) { Database.connect(ENV["DATABASE_URL"]) }

app.get "/users/:id" do |req, db:|
  db.find_user(req.params[:id])
end
```

### Class-based style (structured apps)

```ruby
# endpoints/chat.rb — auto-loaded by Whoosh from endpoints/ directory
class ChatEndpoint < Whoosh::Endpoint
  post "/chat", request: ChatRequest, response: ChatResponse, mcp: true

  def call(req)
    result = llm.complete(req.message)
    { reply: result.text, tokens: result.usage }
  end
end
```

Auto-loading: Whoosh scans `endpoints/**/*.rb` at boot using `Dir.glob` and registers each `Whoosh::Endpoint` subclass. This is how the generated project structure (`endpoints/health.rb`) connects to the app.

### Features

- HTTP verbs: `get`, `post`, `put`, `patch`, `delete`, `options`
- `request:` and `response:` params auto-validate and auto-document
- Route groups with shared prefix, middleware, and metadata
- `app.provide` registers dependencies, injected via keyword args
- Return a Hash or schema object — framework handles JSON serialization
- `:id` style path params, automatically coerced if schema defines the type

## Schema & Validation

```ruby
class ChatRequest < Whoosh::Schema
  field :message,     String,  required: true, desc: "The user message"
  field :model,       String,  default: "claude-sonnet-4-20250514", desc: "Model to use"
  field :temperature, Float,   default: 0.7, min: 0.0, max: 2.0
  field :max_tokens,  Integer, default: 1024, min: 1, max: 100_000
  field :stream,      Whoosh::Types::Bool, default: false
  field :metadata,    Hash,    optional: true
end

class ChatResponse < Whoosh::Schema
  field :reply,       String,  required: true
  field :model,       String
  field :tokens,      TokenUsage
  field :created_at,  Time
end

class TokenUsage < Whoosh::Schema
  field :prompt,      Integer
  field :completion,  Integer
  field :total,       Integer
end
```

- `Whoosh::Schema` wraps dry-schema and dry-types internally
- `field` declarations generate: dry-schema contract, JSON serializer, OpenAPI 3.1 schema
- `Whoosh::Types::Bool` is a framework-provided type alias mapping to `Dry::Types['bool']` (Ruby has no native `Bool` class)
- Nested schemas supported
- Coercion: String `"42"` to Integer `42` automatically
- `Time` fields serialize to ISO 8601 format (`2026-03-11T10:30:00Z`)

### JSON Serialization

- Uses Ruby stdlib `json` by default. Users can configure `Oj` for performance:
  ```ruby
  app.config.json_engine = :oj  # requires oj gem in Gemfile
  ```
- Custom type serializers registered via `Whoosh::Schema.serializer_for(Type, &block)`
- `BigDecimal` serializes as string by default (precision-safe), configurable to float

### Error Responses

All errors follow a consistent JSON structure:

```json
{
  "error": "validation_failed",
  "details": [
    { "field": "temperature", "message": "must be less than or equal to 2.0", "value": 5.0 }
  ]
}
```

Error types and HTTP status codes:
- `validation_failed` → 422
- `not_found` → 404
- `unauthorized` → 401
- `forbidden` → 403
- `rate_limited` → 429 (includes `Retry-After` header)
- `internal_error` → 500 (details omitted in production, full trace in development)

### Global Error Handler

```ruby
app.on_error do |error, req|
  # Custom error handling — logging, alerting, etc.
  Logger.error(error, path: req.path)

  # Return a custom response, or nil to use framework default
  { error: "something_went_wrong", request_id: req.id }
end

# Per-exception-type handlers
app.on_error(Whoosh::RateLimitExceeded) do |error, req|
  { error: "rate_limited", retry_after: error.retry_after }
end
```

## MCP Server & Client

Targets MCP specification version 2025-03-26. Supports stdio and SSE transports. Streamable HTTP transport is planned for a future release.

### MCP Server — Expose endpoints as MCP tools

```ruby
# Any endpoint can be MCP-exposed
app.post "/summarize", request: SummarizeRequest, mcp: true do |req|
  text = loader.load(req.url)
  keywords = keyword.extract(text)
  { summary: llm.summarize(text), keywords: keywords }
end

# Or expose all endpoints in a group
app.group "/tools", mcp: true do
  post "/translate", request: TranslateRequest do |req|
    { result: llm.translate(req.text, to: req.language) }
  end
end
```

When `mcp: true`:
- Endpoint registered as MCP tool automatically
- Schema `desc` fields generate tool descriptions
- MCP protocol negotiation handled (JSON-RPC 2.0, stdio/SSE transport)
- Inputs validated through same dry-schema contracts

CLI:
```bash
whoosh mcp              # stdio transport (Claude Desktop, etc.)
whoosh mcp --sse        # SSE transport (web clients)
whoosh server           # HTTP + MCP SSE on /mcp
```

### MCP Client — Call external MCP servers

```ruby
app.mcp_client :filesystem, command: "npx @modelcontextprotocol/server-filesystem /tmp"
app.mcp_client :github, command: "npx @modelcontextprotocol/server-github"

app.post "/analyze-repo" do |req, mcp_clients:|
  files = mcp_clients[:github].call("list_files", repo: req.repo)
  { result: llm.analyze(files) }
end
```

### MCP Client Process Lifecycle

- **Spawn:** Client process started on first `call()` invocation (lazy)
- **Health check:** Periodic ping via MCP `ping` method (every 30s, configurable)
- **Restart policy:** On health check failure or process exit — max 3 retries with exponential backoff (1s, 2s, 4s). After max retries, accessor raises `Whoosh::MCP::ClientUnavailable`
- **In-flight requests:** During restart, queued requests wait up to `mcp_client_timeout` (default 10s), then raise `Whoosh::MCP::TimeoutError`
- **PID tracking:** Tracked in `Whoosh::MCP::ClientManager`, cleaned up on app shutdown
- **Shutdown:** All client processes sent SIGTERM on app shutdown, SIGKILL after 5s grace period

### Transport Details

- stdio for desktop AI clients (Claude Desktop, etc.)
- SSE for web/remote clients
- Schema reuse: dry-schema contracts become MCP tool input schemas
- Same app serves HTTP and MCP simultaneously

## Authentication & Security

```ruby
# Auth strategies
app.auth do
  api_key header: "X-API-Key", store: :redis
  jwt secret: ENV["JWT_SECRET"], algorithm: :hs256, expiry: 3600
  oauth2 provider: :custom, token_url: "/oauth/token"
end

# Rate limiting
app.rate_limit do
  default limit: 60, period: :minute
  rule "/chat",       limit: 10,  period: :minute
  rule "/embeddings", limit: 100, period: :minute
  tier :free,       limit: 100,  period: :day
  tier :pro,        limit: 5000, period: :day
  tier :enterprise, unlimited: true
  store :redis
  on_store_failure :fail_open  # :fail_open (allow) or :fail_closed (deny)
end

# Token usage tracking
app.token_tracking do
  on_usage do |key, endpoint, tokens|
    Billing.record(api_key: key, tokens: tokens)
  end
end

# Per-key model access control
app.access_control do
  role :basic,    models: ["claude-haiku"]
  role :standard, models: ["claude-haiku", "claude-sonnet"]
  role :premium,  models: ["claude-haiku", "claude-sonnet", "claude-opus"]
end
```

Built-in security defaults (always on):
- CORS with safe defaults (configurable)
- Request size limits (default 1MB, configurable)
- Input sanitization on string fields
- Security headers (Helmet-style)
- MCP request signing and verification
- HTTPS enforcement in production

## Streaming & AI Patterns

Three streaming APIs, each for a different use case:

| API | Wire Format | Use Case |
|-----|------------|----------|
| `stream :sse` | SSE (`text/event-stream`) with named events | Generic server-sent events |
| `stream_llm` | SSE with `data:` chunks (OpenAI-compatible format) | LLM token streaming |
| `websocket` | WebSocket frames | Bidirectional interactive chat |

In all cases, `out << chunk` sends data to the client. For `stream :sse`, `chunk` is auto-serialized to JSON. For `stream_llm`, `chunk` is a `RubyLLM::Chunk` object (or string) — the framework extracts `.text` and wraps it in SSE `data:` format. For `websocket`, `chunk` is sent as a text frame.

```ruby
# SSE streaming — generic events
app.get "/events" do
  stream :sse do |out|
    out.event("status", { msg: "connected" })
  end
end

# LLM streaming — token-by-token responses
app.post "/chat", request: ChatRequest do |req|
  stream_llm do |out|
    llm.stream(req.message, model: req.model) do |chunk|
      out << chunk
    end
  end
end

# Streaming with guardrails — real-time content filtering
app.post "/safe-chat", request: ChatRequest do |req|
  stream_llm do |out|
    buffer = ""
    llm.stream(req.message) do |chunk|
      buffer << chunk.text
      if buffer.end_with?(".", "!", "?")
        guardrails.check!(buffer)  # raises Whoosh::GuardrailsViolation
        out << buffer
        buffer = ""
      end
    end
  end
end

# Long-running inference with progress
app.post "/batch-process", request: BatchRequest do |req|
  stream :sse do |out|
    req.items.each_with_index do |item, i|
      result = ner.recognize(item.text)
      out.event("progress", { current: i + 1, total: req.items.size, result: result })
    end
    out.event("done", { status: "complete" })
  end
end

# WebSocket for interactive chat
app.websocket "/ws/chat" do |ws|
  ws.on_message do |msg|
    stream_llm(ws) do |out|
      llm.stream(msg) { |chunk| out << chunk }
    end
  end
end
```

### Streaming error handling

- **`guardrails.check!` violation:** Sends SSE `event: error` with `{ error: "content_filtered", reason: "..." }`, then closes the stream
- **Client disconnect:** Detected via Rack hijack socket state. In-flight LLM generation is cancelled (if the LLM client supports it). No exception raised server-side.
- **LLM API error mid-stream:** Sends SSE `event: error` with `{ error: "llm_error", message: "..." }`, then closes the stream
- **Backpressure:** Built-in buffering (default 64KB). If buffer fills, back-pressures the producer (fiber yields in Falcon, thread blocks in Puma)

## Plugin System & Gem Auto-Discovery

```ruby
# Just add gems to Gemfile — they're auto-discovered
# Gemfile
gem "lingua-ruby"
gem "ner-ruby"
gem "guardrails-ruby"
gem "ruby_llm"         # <-- required for llm accessor

# In endpoints — they're just available:
app.post "/analyze" do |req|
  lang     = lingua.detect(req.text)
  entities = ner.recognize(req.text)
  keywords = keyword.extract(req.text)
  { language: lang, entities: entities, keywords: keywords }
end
```

### Plugin accessor scope

Plugin accessors (`lingua`, `ner`, `llm`, etc.) are methods on the `Whoosh::App` instance. Inside endpoint blocks, `self` is an `Endpoint::Context` that delegates unknown methods to the app. This means plugin accessors are available as bare method calls inside endpoint blocks and class-based endpoints. They are application-scoped singletons (initialized once, reused across requests).

### Auto-discovery mechanism

1. Scan Gemfile.lock for recognized gem names at boot
2. Register lazy-loaded accessor for each
3. Gem required + initialized on first method call (thread-safe via Mutex)
4. Zero cost if never called

### Configuration and overrides

```ruby
app.plugin :lingua do
  languages [:en, :id, :ms, :ja]
end

app.plugin :guardrails do
  language_check enabled: true, allowed: [:en, :id]
  pii_detection enabled: true
end

app.plugin :ner, enabled: false  # disable

app.plugin :custom_model, class: MyCustomModel do  # custom plugin
  model_path "/models/custom.onnx"
end
```

### Plugin hooks — gems participate in request lifecycle

```ruby
module Whoosh::Plugins::GuardrailsRuby
  def self.middleware? = true

  def self.before_request(req, config)
    Guardrails.check_input!(req.body, config)
  end

  def self.after_response(res, config)
    Guardrails.check_output!(res.body, config)
  end
end
```

### Gem mapping

| Gem | Accessor | Auto-middleware? |
|-----|----------|-----------------|
| ruby_llm | `llm` | No |
| lingua-ruby | `lingua` | No |
| keyword-ruby | `keyword` | No |
| ner-ruby | `ner` | No |
| loader-ruby | `loader` | No |
| prompter-ruby | `prompter` | No |
| chunker-ruby | `chunker` | No |
| guardrails-ruby | `guardrails` | Yes |
| rag-ruby | `rag` | No |
| eval-ruby | `eval_` | No |
| connector-ruby | `connector` | No |
| sastrawi-ruby | `sastrawi` | No |
| pattern-ruby | `pattern` | No |
| onnx-ruby | `onnx` | No |
| tokenizer-ruby | `tokenizer` | No |
| zvec-ruby | `zvec` | No |
| reranker-ruby | `reranker` | No |

## Dependency Injection

```ruby
# Register a singleton (block called once, result cached)
app.provide(:db) { Database.connect(ENV["DATABASE_URL"]) }

# Register a per-request dependency (block called each request)
app.provide(:current_user, scope: :request) do |req|
  User.find_by_token(req.headers["Authorization"])
end

# Dependencies can depend on other dependencies
app.provide(:repo) do |db:|
  UserRepository.new(db)
end

# Inject into endpoints via keyword args
app.get "/users/:id" do |req, repo:|
  repo.find(req.params[:id])
end
```

Scopes:
- `:singleton` (default) — Block called once on first use, result cached for app lifetime. Use for database pools, API clients, configuration.
- `:request` — Block called per request, receives the `Whoosh::Request` as first argument. Use for current user, request-scoped state.

Resolution: Dependencies are resolved via topological sort at boot. Circular dependencies raise `Whoosh::DependencyError` at startup, not at runtime.

`app.provide` vs plugin auto-discovery: `app.provide` is for app-specific dependencies (database, repos, custom services). Plugin auto-discovery is for ecosystem gems. If both define the same accessor name, `app.provide` wins (explicit overrides auto-discovery).

## Configuration

### app.yml

```yaml
# config/app.yml
app:
  name: "My AI API"
  env: <%= ENV.fetch("WHOOSH_ENV", "development") %>
  port: 9292
  host: "localhost"

server:
  type: falcon     # falcon | puma
  workers: auto    # auto = CPU count
  timeout: 30

logging:
  level: info      # debug | info | warn | error
  format: json     # json | text

docs:
  enabled: true    # auto-disabled in production unless overridden
```

### plugins.yml

```yaml
# config/plugins.yml
lingua:
  languages: [en, id, ms, ja]

guardrails:
  language_check:
    enabled: true
    allowed: [en, id]
  pii_detection:
    enabled: true

ner:
  enabled: false
```

### Precedence (highest to lowest)

1. Environment variables (`WHOOSH_PORT=3000`)
2. Ruby DSL config (`app.config.port = 3000`)
3. `config/app.yml`
4. Framework defaults

Config is accessible at runtime via `app.config`:
```ruby
app.config.port       # => 9292
app.config.app.name   # => "My AI API"
```

## Rack Integration

### config.ru

```ruby
# config.ru — generated by `whoosh new`
require_relative "app"

# app.rb exports the Whoosh::App instance
run MyApp.to_rack
```

`Whoosh::App#to_rack` returns a frozen Rack-compatible lambda (`call(env)`). This is the bridge between Whoosh's DSL and any Rack server.

### CLI relationship

- `whoosh server` reads `config.ru` and starts Falcon (or configured server)
- `whoosh console` loads `app.rb` and starts IRB with the app instance available as `app`

## CLI

Built on Thor:

```bash
whoosh new myapp                    # scaffold project
whoosh new myapp --minimal          # bare bones
whoosh new myapp --full             # all gems included

whoosh server                       # Falcon on localhost:9292
whoosh server -p 3000              # custom port
whoosh server --reload             # auto-reload on changes

whoosh routes                       # list all routes

whoosh generate endpoint chat       # endpoint + schema + test
whoosh generate schema User         # schema file
whoosh generate plugin my_plugin    # plugin boilerplate

whoosh console                      # IRB with app loaded

whoosh mcp                          # MCP stdio transport
whoosh mcp --sse                   # MCP SSE transport
whoosh mcp --list                  # list MCP tools
```

### Generated project structure

```
myapp/
├── app.rb                 # Main entry point, defines Whoosh::App
├── config/
│   ├── app.yml            # App configuration
│   └── plugins.yml        # Plugin overrides
├── endpoints/
│   └── health.rb          # Example class-based endpoint
├── schemas/
│   └── health.rb          # Example schema
├── middleware/
│   └── .keep
├── test/
│   ├── test_helper.rb
│   └── endpoints/
│       └── health_test.rb
├── Gemfile
├── Rakefile
├── config.ru              # Rack entry point
└── .env.example
```

## OpenAPI & Auto-Docs

```ruby
# Auto-generated from routes and schemas
# Enabled by default in development:
app.docs enabled: true              # Swagger UI at /docs
app.docs redoc: true                # ReDoc at /redoc

# Customization:
app.openapi do
  title "My AI API"
  version "1.0.0"
  description "AI-powered text analysis API"
  server url: "https://api.example.com", description: "Production"
end
```

- Swagger UI assets vendored in the gem (~3MB compressed). Versioned and updated with gem releases. Licensed Apache 2.0.
- OpenAPI 3.1 spec at `/openapi.json`
- Everything auto-generated from schemas and routes — zero extra annotations needed
- Dev on, prod off by default. Opt-in for production: `app.docs enabled: true, auth: :api_key`

## Logging & Observability

```ruby
# Structured JSON logging (default in production)
app.logging do
  level :info
  format :json  # or :text for development
end

# Log output example:
# {"ts":"2026-03-11T10:30:00Z","level":"info","method":"POST","path":"/chat","status":200,"duration_ms":142,"tokens":{"prompt":50,"completion":120}}

# Request ID — auto-generated, passed through X-Request-ID header
# All log entries include request_id for tracing

# Custom log context
app.post "/chat" do |req|
  logger.info("chat_start", model: req.model, user: current_key.id)
  # ...
end
```

Token usage and rate limit events are logged automatically when those features are enabled.

## Graceful Shutdown

On `SIGTERM` or `SIGINT`:

1. Stop accepting new connections
2. Wait for in-flight requests to complete (grace period: 30s, configurable via `app.config.shutdown_timeout`)
3. Send SSE `event: close` to all active streaming connections
4. Terminate MCP client subprocesses (SIGTERM, then SIGKILL after 5s)
5. Close database connections and other singleton dependencies (if they respond to `#close`)
6. Exit with status 0

If grace period expires, forcefully terminate remaining requests and exit.

## Concurrency Safety

- **Plugin registry:** Lazy initialization protected by `Mutex`. After initialization, accessor is a direct reference (no lock contention on subsequent calls).
- **Dependency injection:** Singleton dependencies initialized under `Mutex`. Request-scoped dependencies created per-request (no sharing).
- **Rate limiter:** Redis operations are atomic (MULTI/EXEC). In-memory store uses `Concurrent::Hash` for thread safety.
- **Router:** Immutable after boot. No locking needed.
- **Plugins:** Ecosystem gems are expected to be stateless or internally thread-safe. Whoosh documents this contract for plugin authors.

## Internal Structure

```
lib/
└── whoosh/
    ├── app.rb
    ├── router.rb
    ├── request.rb
    ├── response.rb
    ├── schema.rb
    ├── types.rb                    # Whoosh::Types::Bool and custom types
    ├── config.rb                   # Configuration loading (YAML + ENV + DSL)
    ├── dependency_injection.rb
    ├── endpoint.rb                 # Class-based endpoint base class
    ├── errors.rb                   # Error types and error handler
    ├── logger.rb                   # Structured logging
    ├── middleware/
    │   ├── stack.rb
    │   ├── cors.rb
    │   ├── logger.rb
    │   ├── security_headers.rb
    │   └── request_limit.rb
    ├── auth/
    │   ├── api_key.rb
    │   ├── jwt.rb
    │   ├── oauth2.rb
    │   ├── rate_limiter.rb
    │   ├── token_tracker.rb
    │   └── access_control.rb
    ├── mcp/
    │   ├── server.rb
    │   ├── client.rb
    │   ├── client_manager.rb       # PID tracking, lifecycle, shutdown
    │   ├── protocol.rb
    │   └── transport/
    │       ├── stdio.rb
    │       └── sse.rb
    ├── streaming/
    │   ├── sse.rb
    │   ├── websocket.rb
    │   └── llm_stream.rb
    ├── openapi/
    │   ├── generator.rb
    │   ├── ui.rb
    │   ├── schema_converter.rb
    │   └── assets/                 # Vendored Swagger UI
    ├── plugins/
    │   ├── registry.rb
    │   ├── base.rb
    │   └── adapters/
    │       ├── lingua_ruby.rb
    │       ├── ner_ruby.rb
    │       ├── keyword_ruby.rb
    │       ├── guardrails_ruby.rb
    │       ├── loader_ruby.rb
    │       ├── prompter_ruby.rb
    │       ├── chunker_ruby.rb
    │       ├── rag_ruby.rb
    │       ├── eval_ruby.rb
    │       ├── connector_ruby.rb
    │       ├── sastrawi_ruby.rb
    │       ├── pattern_ruby.rb
    │       ├── onnx_ruby.rb
    │       ├── tokenizer_ruby.rb
    │       ├── zvec_ruby.rb
    │       ├── reranker_ruby.rb
    │       └── ruby_llm.rb
    └── cli/
        ├── main.rb
        ├── commands/
        │   ├── new.rb
        │   ├── server.rb
        │   ├── routes.rb
        │   ├── generate.rb
        │   ├── console.rb
        │   └── mcp.rb
        └── templates/
            ├── new/
            ├── endpoint.rb.tt
            ├── schema.rb.tt
            └── plugin.rb.tt
```

## Dependencies

### Hard (always installed)

- `rack` ~> 3.0
- `dry-schema` ~> 1.13
- `dry-types` ~> 1.7
- `thor` ~> 1.3

### Optional (user installs as needed)

- `falcon` — async server (recommended)
- `puma` — threaded server (alternative)
- `oj` — fast JSON serialization (optional, stdlib json used by default)
- `ruby_llm` — LLM API access
- All ecosystem gems — auto-discovered as plugins

## Testing

### Framework internals — RSpec

```bash
bundle exec rspec
```

### User app testing

Generated projects include Minitest by default (or RSpec via `whoosh new myapp --rspec`).

```ruby
# test/endpoints/health_test.rb
require "test_helper"

class HealthEndpointTest < Whoosh::Test
  def test_health_check
    get "/health"

    assert_response 200
    assert_json({ status: "ok" })
  end

  def test_chat_validates_input
    post "/chat", json: { temperature: 5.0 }

    assert_response 422
    assert_json_path "error", "validation_failed"
  end

  def test_chat_requires_auth
    post "/chat", json: { message: "hello" }

    assert_response 401
  end
end
```

`Whoosh::Test` wraps `Rack::Test` with convenience methods: `assert_response`, `assert_json`, `assert_json_path`, `post_json`. The test helper auto-loads the app from `app.rb`.

## API Versioning

Whoosh supports URL-based versioning via route groups:

```ruby
app.group "/api/v1" do
  post "/chat", request: ChatRequestV1 do |req|
    # v1 behavior
  end
end

app.group "/api/v2" do
  post "/chat", request: ChatRequestV2 do |req|
    # v2 behavior
  end
end
```

No built-in header-based or content-type versioning. URL versioning is explicit, simple, and well-supported by OpenAPI docs (each version group generates its own tagged section).
