# Changelog

All notable changes to this project will be documented in this file.

## [1.9.0] - 2026-04-17

### Added
- **Streaming helpers on `Whoosh::Endpoint`.** Class-based endpoints can now call `stream :sse do |out| … end` and `stream_llm do |out| … end` directly, matching the block-route DSL on `Whoosh::App`. Previously, endpoints had to construct `StreamBody` + `SSE` + headers tuples by hand. The helpers were extracted into `Whoosh::Streaming::Helpers` and mixed into both `App` and `Endpoint` so they stay in sync.

## [1.8.0] - 2026-04-17

### Added
- **Endpoint DI.** `Whoosh::Endpoint` subclasses now support `inject :dep1, :dep2, …` (matching `Whoosh::Job`). Injected deps are resolved from the DI container per request and exposed as accessor methods on the endpoint instance. Request-scoped providers receive the current request. Previously, class-based endpoints had no access to DI — only block routes did, via kwarg injection.

  ```ruby
  class UsersIndex < Whoosh::Endpoint
    get "/users"
    inject :db

    def call(_req)
      db[:users].all
    end
  end
  ```

## [1.7.0] - 2026-04-17

### Changed — BREAKING
- **MCP tool exposure is now opt-in.** Routes are only registered as MCP tools when declared with `mcp: true` (or inside a group with `mcp: true`). Previously, every route was auto-exposed and had to be opted out with `mcp: false`. The old default leaked internal/admin endpoints as callable tools. To restore prior behavior for a route, add `mcp: true` to it explicitly.

### Changed
- Repositioned README around MCP, added "When NOT to use Whoosh" section, reframed performance benchmarks with honest per-core comparisons.

## [1.6.0] - 2026-04-04

### Added — Client Generator (`whoosh generate client <type>`)
- **7 client types** — `react_spa`, `expo`, `ios`, `flutter`, `htmx`, `telegram_bot`, `telegram_mini_app`
- **OpenAPI introspection** — reads existing Whoosh app routes, schemas, and auth config to generate typed clients
- **Fallback scaffolding** — generates standard JWT auth + tasks CRUD backend when no app exists
- **Interactive CLI** — shows detected endpoints, lets you toggle which resources to include
- **`--oauth` flag** — adds Google/GitHub/Apple social login to generated clients
- **react_spa** — React 19 + Vite + TypeScript + React Router, auth hooks, CRUD pages, cursor pagination
- **expo** — Expo SDK 52 + React Native + Expo Router + SecureStore for tokens
- **ios** — SwiftUI + MVVM + async/await + Keychain + NavigationStack
- **flutter** — Dart + Dio + Riverpod + GoRouter + flutter_secure_storage
- **htmx** — Standalone HTML + htmx 2.x + vanilla JS, no build step
- **telegram_bot** — Ruby bot with command handlers, inline keyboards, session store
- **telegram_mini_app** — React + Telegram WebApp SDK, auth via initData, theme-adaptive
- **Dependency checker** — validates platform tools (node, flutter, xcode, ruby) before generating
- **Type mapping engine** — IR types map to TypeScript, Swift, Dart, Ruby, HTML form inputs
- 95 client generator tests, 0 failures

## [1.5.0] - 2026-03-25

### Added — FastAPI Parity (10 gaps closed, ~90% feature parity)
- **Cookie helpers** — `req.cookies["session"]` reads cookies from request
- **Redirect** — `redirect("/new")` and `redirect("/perm", status: 301)`
- **Download** — `download(data, filename: "report.csv")`
- **Static files** — `serve_static("/assets", root: "public/")` with path traversal protection
- **Send file** — `send_file("path/to/file.pdf")`
- **CSP header** — Content-Security-Policy in default security headers
- **Middleware error handling** — compiled handler catches errors, returns JSON 500
- **Custom validators** — `validate_with { |data, errors| ... }` DSL on schemas
- **Query param docs** — `query: FilterSchema` documents params in OpenAPI spec
- **OAuth2 providers** — Google, GitHub, Apple with authorize_url, exchange_code, userinfo
- **Async HTTP** — `HTTP.concurrent(...)` for parallel requests, `HTTP.async.get(...)` for futures
- 564 tests, 0 failures

## [1.4.1] - 2026-03-24

### Fixed — WebSocket works on both Puma AND Falcon
- Auto-detects server: Puma → faye-websocket, Falcon → async-websocket
- `faye-websocket` uses EventMachine (conflicts with Falcon's async reactor)
- `async-websocket` uses Async gem (native to Falcon)
- Same `websocket(env)` API — app code is identical on both servers
- Verified on Puma (macOS dev) and Falcon (Linux production)

## [1.4.0] - 2026-03-24

### Changed — Production WebSocket
- Replaced hand-rolled RFC 6455 with `faye-websocket` (battle-tested, used by Rails ActionCable)
- `faye-websocket` added as hard dependency (WebSocket is core for AI-first framework)
- Works with Puma (macOS dev) and Falcon (Linux production)
- Verified: full round-trip — open, send, receive, close with proper codes
- 542 tests, 0 failures

## [1.3.2] - 2026-03-20

### Fixed
- `whoosh s` auto-detects platform: Puma on macOS (dev), Falcon on Linux (production)
- Falcon forks crash on macOS due to ObjC runtime + native C extensions (pg gem)
- No manual server config needed — just `whoosh s` and it picks the right one

## [1.3.1] - 2026-03-20

### Fixed
- Real WebSocket support with RFC 6455 protocol (handshake, frame encoding/decoding)
- Works with Puma (`rack.hijack`) and Falcon in development
- `websocket(env)` helper available in endpoints
- Proper close frames, ping/pong, masked frame handling

## [1.3.0] - 2026-03-18

### Added — AI First-Class Citizen
- `Whoosh::AI::LLM` — chat, extract (structured output), stream with response caching
- `Whoosh::AI::StructuredOutput` — validate LLM output against Whoosh::Schema
- `whoosh describe` — dump entire app as structured JSON (AI-agent friendly)
- `whoosh check` — validate config, catch common mistakes before runtime
- Generated `CLAUDE.md` in every `whoosh new` project
- All routes auto-exposed as MCP tools (opt-out with `mcp: false`)
- Available as `llm` in endpoints via DI
- 539 tests, 0 failures

## [1.2.2] - 2026-03-18

### Upgraded
- `whoosh ci` expanded to 6 checks: Rubocop, Brakeman, Bundle Audit, Secret Scan, RSpec, Coverage
- Secret scan built-in (no gem needed) — detects hardcoded API keys, AWS keys, private keys
- SimpleCov coverage threshold (80% minimum)

## [1.2.1] - 2026-03-18

### Added
- `whoosh ci` command — Rubocop + Brakeman + RSpec pipeline
- Project generator includes rubocop, brakeman, .rubocop.yml

## [1.2.0] - 2026-03-17

### Added
- VectorStore with cosine similarity search (insert, search, delete, count, drop)
- Auto-detect: zvec gem installed → uses zvec, otherwise → in-memory
- Available as `vectors` in endpoints via DI

## [1.1.0] - 2026-03-17

### Added
- `perform_in(delay)` and `perform_at(time)` for scheduled jobs
- Named queues via `queue :critical` class DSL
- Per-job retry: `retry_limit`, `retry_backoff :exponential`
- Non-blocking retry (re-enqueue with delay timestamp)
- Per-job logging (started, completed, retry, failed)
- Redis backend for jobs with sorted sets for scheduling
- Auto-detect pattern: `REDIS_URL` → Redis, otherwise → Memory (jobs + cache)
- 521 tests, 0 failures

## [1.0.1] - 2026-03-16

### Added
- Whoosh::Test DSL (assert_response, assert_json, post_json, get_with_auth)
- Generator field args, `generate plugin`, `generate proto`
- `whoosh db` CLI (migrate/rollback/status)
- OAuth2 auth strategy with custom validator
- MCP stdio transport, group mcp propagation
- Response schema validation (advisory, development only)
- `app.docs` DSL with ReDoc at `/redoc`
- Graceful shutdown wired into App
- Batteries-included project generator (Falcon, Oj, JWT, rate limiting)
- `whoosh s` works like `rails s`

### Fixed
- Request body.rewind for WEBrick compatibility

## [1.0.0] - 2026-03-16

### Stable Release
- 400 tests, 0 failures
- 45+ source files, ~8000 lines
- Security audit passed (JWT length oracle fixed, OWASP headers verified)
- Thread safety verified under concurrent load
- Framework overhead: 2.5µs per request (406K iterations/s)

## [1.0.0.rc1] - 2026-03-16

### Added
- Security audit tests (JWT signature tampering, CORS reflection, rate limiter bypass)
- CHANGELOG, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, LICENSE

### Fixed
- JWT secure_compare length oracle vulnerability (HMAC-of-HMAC comparison)

## [0.8.0] - 2026-03-16

### Added
- Instrumentation event bus for error tracking and metrics hooks
- Concurrent request stress tests (thread safety verified)

## [0.7.0] - 2026-03-16

### Added
- MCP schema-to-tool inputSchema auto-conversion via SchemaConverter
- MCP SSE transport for web client access
- MCP client subprocess spawning with Open3 and PID tracking
- MCP stdio end-to-end communication verified

## [0.6.0] - 2026-03-16

### Added
- README with quick-start guide and feature overview
- Example chat-api project with auth, streaming, MCP, schemas
- Expo React Native client template with SSE streaming

## [0.5.0] - 2026-03-16

### Added
- Plugin configuration from config/plugins.yml
- PluginHooks middleware (before_request/after_response)
- Plugin adapter integration tests with mock plugins
- Protobuf serialization verification

## [0.4.0] - 2026-03-16

### Added
- Request ID propagation through middleware chain
- Request-scoped logger with context (req.logger)
- Graceful shutdown with hooks and signal handlers
- Built-in /healthz endpoint with configurable probes

## [0.3.0] - 2026-03-16

### Added
- Oj JSON engine auto-detection (5-10x speedup)
- YJIT auto-enable at boot
- Benchmark suite (router, JSON, schema validation)

### Changed
- SecurityHeaders uses in-place mutation (reduced allocations)
- Response.json uses pre-frozen headers
- Router static route cache for O(1) lookup
- Frozen empty params hash

## [0.2.0] - 2026-03-16

### Added
- End-to-end integration tests (42 examples)
- Edge case tests for all modules (30 examples)
- GitHub Actions CI pipeline

### Fixed
- Schema validate(nil) crash
- Router trailing slash matching

## [0.1.0] - 2026-03-15

### Added
- Core framework: trie-based router, dry-schema validation, DI, middleware
- Plugin system with auto-discovery from Gemfile.lock
- Class-based endpoints with Context delegation
- API key and JWT authentication
- Rate limiting with tiers and fail-open/closed
- Token usage tracking and access control
- SSE, LLM streaming, WebSocket
- MCP server and client (JSON-RPC 2.0)
- MessagePack and Protobuf serializer interfaces
- Database module (Sequel integration)
- OpenAPI 3.1 auto-generation with Swagger UI
- Thor-based CLI with generators
