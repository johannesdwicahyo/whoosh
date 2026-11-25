# Changelog

## 2.0.0 (2026-11-25)

A ground-up rewrite. Whoosh 2 shares no code and no API with 1.x, which was a different, much larger framework; its history is on the `1.x` branch. The same code was briefly published as 0.1.0.

- `Whoosh::API` classes are Rack apps: `run` standalone, or `mount` in Rails, Sinatra, Hanami
- Deny-by-default endpoints: each must declare `authorize` or `public!`, and `returns`, or definition fails
- `Whoosh::Schema` for input (coercion, validation, unknown keys dropped) and output (only declared fields serialized)
- One error envelope with request IDs; Active Record errors translated
- Limits on body size, JSON depth and key count, string length, array length and page size
- Per-endpoint rate limiting keyed by user or IP, including failed logins
- Idempotency keys with replay and reuse detection
- Cursor and offset pagination without COUNT(*)
- Closed-by-default CORS, security headers, HSTS over HTTPS
- OpenAPI 3.1 generation, optionally served at /openapi.json
- Memory and ActiveSupport::Cache stores; Rails Railtie and `whoosh:install` generator
- One runtime dependency: bigdecimal
