# Whoosh Milestones: v0.1.0 → v1.0.0

## Current State (v0.1.0)

- 268 tests, 0 failures
- 42 source files, ~7500 lines
- 8 phases complete: Core, Plugins, Auth, Streaming, MCP, Serialization, OpenAPI, CLI
- Functional but not production-tested

---

## v0.1.1 — Immediate Fixes

- Fix `spec.files` glob pattern in gemspec (currently missing — gem can't be built)
- Ensure `gem build whoosh.gemspec` succeeds and includes all lib/ files

---

## v0.2.0 — Hardening & CI

**Goal:** Production confidence through testing and CI. Must come before performance work — can't optimize what isn't proven correct.

- **CI/CD pipeline** — GitHub Actions with Ruby 3.4+ test matrix, lint, security scan (basic pipeline now; release automation deferred to v0.10.0)
- Integration tests (end-to-end with real Rack requests via rack-test)
- Edge case coverage (malformed JSON, empty bodies, oversized headers, unicode paths)
- Thread safety verification under concurrent load (concurrent-ruby)
- Error message quality audit (every error should be actionable)
- Middleware ordering tests (verify correct execution order)
- Schema validation edge cases (deeply nested, circular references, huge payloads)
- Auth edge cases (expired JWT, malformed tokens, concurrent rate limit)
- Streaming edge cases (client disconnect mid-stream, backpressure)
- Verify MCP transport files exist (`mcp/transport/stdio.rb`, `mcp/transport/sse.rb` from design spec may be missing — build stubs if needed)

---

## v0.3.0 — Performance (Target: beat FastAPI, approach Fastify)

**Goal:** Achieve 40-60K req/s on simple JSON endpoints. Outperform FastAPI (~30K) and approach Fastify range.

### Optimization Layer 1: JSON Engine (5-10x win)

- **Oj gem integration** — optional dependency, auto-detected
  - `Oj.dump` is 5-10x faster than `JSON.generate`
  - Config: `app.config.json_engine = :oj` (auto from Gemfile)
  - Fallback to stdlib JSON if Oj not present
- **Precompiled JSON serialization** — for known schemas, generate a serializer proc at boot

### Optimization Layer 2: Allocation Reduction

- **SecurityHeaders** — change `HEADERS.merge(headers)` to avoid per-request hash allocation
- **Response.json** — pre-freeze common response header hashes
- **Router.match** — cache segment arrays after freeze; return frozen empty hash for no-param routes
- **Request** — read directly from env hash where possible, avoid unnecessary Rack::Request wrapping

### Optimization Layer 3: Compiled Middleware

- **Boot-time compilation** — compile middleware chain + handler into a single lambda after `to_rack`
- **Conditional middleware** — skip CORS if no `HTTP_ORIGIN`, skip auth if route has no `auth:` metadata

### Optimization Layer 4: Router Optimization

- **Frozen segment cache** — pre-compute segment arrays for all static paths after `freeze!`
- **Method-first dispatch** — separate tries per HTTP method to reduce branching
- **Direct handler lookup** — for static routes (no params), `"GET:/health" => handler` flat hash (O(1))

### Optimization Layer 5: YJIT Tuning

- **Auto-enable YJIT** at boot with `RubyVM::YJIT.enable`
- **Increase exec_mem** to 128MB for larger apps
- **Verify hot methods are JIT-compiled** via `RubyVM::YJIT.stats`

### Optimization Layer 6: Falcon Tuning

- Fiber pool sizing, keep-alive tuning, buffer sizing
- Verify no blocking calls in middleware chain

### Benchmark Suite

- **Benchmark methodology:** single-core comparison, matching concurrency levels, same hardware
- **Micro-benchmarks** — router match, JSON encode, middleware chain, schema validation (benchmark-ips)
- **Load test** — wrk/h2load against Falcon
- **Comparison test** — same endpoint on Whoosh vs FastAPI vs Fastify (documented methodology)
- **Memory profiling** — allocations per request (memory_profiler gem)
- **Boot time** — cold start measurement

### Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Simple JSON GET | 40-60K req/s | Oj + compiled middleware + cached routes |
| Schema-validated POST | 15-25K req/s | dry-schema has allocation overhead; FastAPI+Pydantic does ~8-12K |
| Concurrent SSE streams | 10K+ connections | Falcon fibers |
| Framework overhead | <0.3ms per request | Allocation reduction |
| Boot time | <300ms | Lazy loading verification |

> **Note:** Do not publish benchmark comparisons until methodology is documented and reproducible.

---

## v0.4.0 — Real-World Readiness

**Goal:** Features needed for actual deployment and development workflow.

- **Graceful shutdown** — SIGTERM/SIGINT handling, connection draining, configurable grace period
- **Config validation** — reject invalid config at boot with clear error messages
- **Request ID propagation** — pass request_id through entire middleware chain and into logs
- **Request-scoped logger** — wire existing `Whoosh::Logger` into request context; expose `req.logger` on `Whoosh::Request` with automatic request_id
- **Structured logging consistency** — ensure all components (auth, rate limiter, MCP, plugins) read from the same configured log level, not hardcoding `$stdout`
- **Health check endpoint** — built-in `/healthz` with configurable checks (DB, external services)
- **Request timeout** — configurable per-route timeout with clean error response
- **`whoosh server --reload`** — file watcher with auto-restart (needed for plugin development)
- **`whoosh console` improvements** — preloaded app instance, helper methods
- **HTTPS awareness** — log a warning when `WHOOSH_ENV=production` and request is plain HTTP; document reverse proxy configuration. Full redirect logic is optional middleware, not always-on (avoids proxy loop footgun).

---

## v0.5.0 — Plugin Ecosystem Validation

**Goal:** Prove the plugin system works with real gems.

**Prerequisite:** Verify that at least 3 of the top-5 ecosystem gems (lingua-ruby, ner-ruby, ruby_llm, keyword-ruby, guardrails-ruby) are published and installable from RubyGems. If not ready, build stub/mock adapters for testing so the plugin system can be validated independently.

- Test with real gems (or stubs) for at minimum 3 plugins
- Plugin adapter implementations for top 5 gems
- Plugin configuration from `config/plugins.yml`
- Plugin hook middleware integration (before_request/after_response in request pipeline)
- Plugin dependency resolution (gem A requires gem B)
- Protobuf serialization integration and testing (same optional-gem discovery pattern)
- Document plugin authoring guide

---

## v0.6.0 — Developer Experience

**Goal:** Make development fast and pleasant.

- README with quick-start guide and examples
- Development error pages (stack traces, request info, route details)
- `whoosh routes` with column-aligned output, color, and metadata
- Generator improvements (field arguments: `whoosh generate schema User name:string email:string`)
- `whoosh db` commands working with Sequel migrations
- Request/response logging in development (pretty-printed, not JSON)

---

## v0.7.0 — MCP Production Ready

**Goal:** MCP works with real AI clients.

- MCP stdio transport tested with Claude Desktop
- MCP SSE transport implementation (for web clients)
- Schema-to-MCP tool input schema automatic conversion (from dry-schema fields)
- MCP client subprocess spawning with actual `Open3.popen3`
- Health check ping (30s interval) and restart with exponential backoff (3 retries)
- PID tracking and graceful SIGTERM/SIGKILL cleanup
- MCP request validation and error responses

---

## v0.8.0 — Production Hardening

**Goal:** Safe to run under real production load.

- Redis adapter for rate limiter (optional dependency)
- Connection pool management for database (verify Sequel integration)
- Memory leak testing (simulate 24h+ running process)
- Load testing under sustained traffic (not just burst)
- Error tracking integration hooks (Sentry, Honeybadger, etc.)
- Metrics hooks (request count, latency histogram, error rate)

---

## v0.9.0 — Documentation & Polish

**Goal:** Ready for public consumption.

- Full API documentation (YARD)
- Tutorial: building a chat API with Whoosh
- Tutorial: adding MCP tools to an existing app
- Tutorial: versioning an API with route groups
- Tutorial: deploying Whoosh to production (Docker, systemd)
- CHANGELOG.md
- CONTRIBUTING.md
- Code of conduct
- Security policy (SECURITY.md)

---

## v0.10.0 — Release Candidate

**Goal:** Final pre-release verification.

- Security audit (OWASP top 10 review of all auth code)
- Dependency audit (minimize attack surface)
- Deprecation policy defined
- Semantic versioning commitment documented
- Release automation (gem push, changelog generation)
- Beta testing with 2-3 real projects

---

## v1.0.0 — Stable Release

**Goal:** Public, stable, supported.

- All RC issues resolved
- Public gem release to RubyGems
- GitHub repo public with badges (CI, version, docs)
- Announcement blog post
- README finalized with badges, examples, benchmarks

---

## Future (post-v1.0) — Revisit List

Items deferred for later evaluation based on real benchmark data:

- **Ractor parallelism** — true parallel execution bypassing GVL. Requires redesigning state sharing. Evaluate if B-tier optimizations hit a ceiling.
- **io_uring on Linux** — kernel-level async I/O for Falcon. Linux-only. Evaluate when deploying to Linux production.
- **Native C extension for hot path** — C-level JSON serializer or router. Evaluate only if pure Ruby optimizations plateau below target.
- **HTTP/3 (QUIC)** — next-gen protocol support. Wait for Rack ecosystem support.
- **gRPC transport** — for high-performance service-to-service. Evaluate based on user demand.
- **WebAssembly (WASI) deployment** — run Whoosh in edge runtimes. Experimental.
