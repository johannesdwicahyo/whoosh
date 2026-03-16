# Changelog

All notable changes to this project will be documented in this file.

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
