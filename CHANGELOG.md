# Changelog

## 2.2.0 (2026-11-26)

- `bin/rails g whoosh:api Orders` writes a list and a show endpoint, a schema from the model's columns and a test, and adds the class to the mount line. Credential-like columns are left out of the schema; Rails enums become strings
- `api_sign_in user` in Rails request specs and integration tests makes requests as that user without a token. `Whoosh::TestHelpers` for everything else
- `rake bench:http`: an HTTP benchmark against Grape and a plain Rails controller, with results in the README
- `BENCH_BUDGET=10,30 rake bench` fails when the speed budget is exceeded; CI runs it

## 2.0.2 (2026-11-26)

- `scale:` on decimal fields. `field :price, :decimal, scale: 2` serializes 2000.5 as `"2000.50"`, and rejects input with more decimal places. Without `scale:` nothing changes

## 2.0.1 (2026-11-26)

Found by building a new Rails app on the published gem.

- In Rails tests, rate limits and idempotency keys are cleared before every example (RSpec and `ActiveSupport::TestCase`). Before this, one test's requests could rate-limit another
- One log line per request with method, path, status, duration and request ID, written to `config.logger` at info level
- README: a Testing section, and a note on sharing an `authorize` rule through `helpers`

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
