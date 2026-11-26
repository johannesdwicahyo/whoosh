# Whoosh

An opinionated, secure-by-default JSON API framework for Ruby. Run it on its own, or mount it inside Rails, Sinatra or Hanami and use your existing models.

> Whoosh 2 is a ground-up rewrite and shares nothing with 1.x. It is new, so expect the API to move before 3.0. The old framework is on the [`1.x` branch](https://github.com/johannesdwicahyo/whoosh/tree/1.x).

```ruby
class OrdersApi < Whoosh::API
  version 1

  get "/orders" do
    authorize { |user| user.staff? }
    params { optional :status, :string, enum: Order.statuses.keys }
    paginate
    returns OrderSchema
    handle { |p| current_user.store.orders.then { |o| p[:status] ? o.where(status: p[:status]) : o } }
  end

  post "/orders" do
    authorize { |user| user.can_sell? }
    idempotent
    params do
      required :customer_id, :integer
      required :items, :array, max_items: 50 do
        required :product_id, :integer
        required :quantity, :integer, min: 1, max: 999
      end
    end
    returns OrderSchema
    handle { |p| Orders::Create.call(p, by: current_user) }
  end
end
```

## What "secure by default" means

An endpoint can't leak data, skip auth or accept unchecked input unless you write that down:

- **Deny by default.** Every endpoint must have `authorize { ... }` or `public!`, plus `returns` and `handle`. If one is missing, the class fails to load, so the app never boots with an open endpoint.
- **Declared input only.** Path, query and JSON body are merged and run through the `params` schema. Values are coerced and validated, and undeclared keys are dropped before the handler sees them, so mass assignment can't happen.
- **Declared output only.** Responses are serialized through the `returns` schema. A new `password_digest` column never ends up in JSON.
- **Limits everywhere:**
  - 1 MB bodies
  - JSON depth 20 and at most 1,000 keys
  - strings capped at 10,000 characters
  - arrays capped at 100 items
  - at most 100 rows per page
  - 300 requests per minute per user or IP, per endpoint
- **Rate limits apply before the 401 check**, so token guessing is throttled.
- **One error envelope** for every failure, with a request ID. In production a 500 never includes the exception message.
- **Locked-down headers:**
  - CORS is closed until you list origins
  - `nosniff`, `DENY` framing and `no-store` caching are on
  - a restrictive CSP is set
  - HSTS is sent over HTTPS
- **Idempotency keys** let unsafe endpoints like payments be retried safely.

## Why not Grape, or Rails with rack-attack, Pundit and a serializer?

Both work, and both are far more mature than Whoosh. The difference is what happens when someone forgets a step.

| | Rails + rack-attack + Pundit + serializer | Grape | Whoosh |
| --- | --- | --- | --- |
| Endpoint with no access rule | Works, unless you added `verify_authorized`, which fails at request time | Works | Class fails to load |
| Undeclared input | Dropped if you remember `permit` | Reaches the handler unless you call `declared(params)` | Always dropped |
| Undeclared output | Depends on the serializer you picked | Whatever you return, unless you use an entity | Never serialized |
| Rate limits, idempotency keys, pagination caps | Separate gems and your own code | Separate gems and your own code | Built in, on by default |
| OpenAPI | Separate gem, often written by hand | Separate gem | Generated from the same schemas |

Pick Grape or plain Rails if you need XML, file uploads, streaming or a large plugin ecosystem. Whoosh only does JSON, and it is new.

## Install

```ruby
gem "whoosh", "~> 2.0"
```

The only runtime dependency is `bigdecimal`, which Rails already pulls in. Whoosh speaks the Rack spec directly, and uses Oj for JSON when your app has it loaded.

### In Rails

```sh
bin/rails g whoosh:install
```

This creates `config/initializers/whoosh.rb`, `app/api/application_api.rb`, a status endpoint, and this route:

```ruby
# config/routes.rb
mount Whoosh.app("StatusApi", "OrdersApi"), at: "/api"
```

Pass class names as strings so development code reloading works. Every API class has to be listed here; one you leave out answers 404. Handlers use your Active Record models, policies and service objects as usual. In Rails:

- `RecordNotFound` becomes a 404.
- `RecordInvalid` becomes a 422 with field errors.
- `RecordNotUnique` becomes a 409.
- Rate limits and idempotency keys are stored in `Rails.cache`, so they're shared across Puma workers.

### Standalone or Sinatra

```ruby
# config.ru
require "whoosh"
require_relative "api/orders_api"
run OrdersApi                       # or: run Whoosh.app(OrdersApi, CustomersApi)
```

In Sinatra, `map("/api") { run OrdersApi }` in `config.ru`. See `examples/config.ru` for a complete app.

## Authentication

You provide one lambda that maps a request to a user (or `nil`):

```ruby
Whoosh.configure do |config|
  config.authenticate = lambda do |request|
    token = request.bearer_token
    token && ApiToken.active.find_by(digest: Digest::SHA256.hexdigest(token))&.user
  end
end
```

Store token digests, never raw tokens. `request.bearer_token` only accepts a well-formed `Authorization: Bearer ...` header.

## Endpoint DSL

| Method | Purpose |
| --- | --- |
| `public!` | Anyone may call it. Otherwise a missing user gets 401. |
| `authorize { \|user, params\| ... }` | Falsey means 403. Runs after params are parsed. |
| `params { required/optional ... }` or `params SomeSchema` | Accepted input. Path params are added as strings if you don't declare them. |
| `returns Schema`, `returns Schema, many: true`, `returns nil` | Response shape. `nil` means 204. POST defaults to 201. |
| `returns { field ... }` | Inline response schema. |
| `paginate`, `paginate :cursor, by: :created_at, order: :desc`, `paginate :offset` | Adds `limit` plus `cursor` or `page`. Never runs `COUNT(*)`. |
| `idempotent`, `idempotent required: true` | Replays repeated `Idempotency-Key` requests. The same key with a different body gets 422. |
| `rate_limit 10, per: 60`, `rate_limit false` | Overrides the default limit. |
| `handle { \|params\| ... }` | Returns the object(s) to serialize. Returning `nil` for a single record gives 404. |
| `summary`, `description`, `tags`, `deprecated!` | OpenAPI docs. |

Inside `authorize` and `handle` you have `current_user`, `params`, `request`, your `helpers`, and:

```ruby
status 202
header "location", "/v1/orders/#{order.id}"
not_found!  forbidden!  conflict!("Already paid")  bad_request!
invalid!(quantity: "is more than the stock left")        # 422, field errors
error!(402, "payment_required", "Top up your balance first.")
```

A rule you repeat can live in `helpers`, since `authorize` blocks can call them:

```ruby
helpers { def staff? = current_user.staff? || current_user.admin? }

get "/orders" do
  authorize { staff? }
  # ...
end
```

Class-level settings:

```ruby
class ApplicationApi < Whoosh::API
  version 1                         # /v1 prefix (declare before endpoints)
  helpers { def current_store = current_user.store }
  rescue_from(Xendit::Error) { |e| Whoosh::HTTPError.new(e.message, status: 502, code: "payment_gateway_error") }
  openapi_info title: "Wicara API", version: "1.0.0"
end
```

## Schemas

```ruby
class OrderSchema < Whoosh::Schema
  field :id, :integer
  field :number, :string
  field :total, :decimal, scale: 2          # serialized as "125000.00", never a float
  field :status, :string, enum: %w[pending paid cancelled]
  field :placed_at, :datetime, from: :created_at
  field :customer, CustomerSchema
  field :items, :array, of: LineItemSchema, from: :line_items
  field :store_name, :string, from: ->(order) { order.store.name }
end
```

- **Types:** `string text integer float decimal boolean date datetime time uuid email url array object json`.
- **Options:** `required default nullable enum min max min_length max_length min_items max_items scale format of from description example deprecated`.
- **Decimals** are strings in JSON. Give them `scale:` to match the database column: at `scale: 2`, 2000.5 goes out as `"2000.50"` and input with more decimal places is a 422. Without it, trailing zeros are dropped (`"2000.5"`).
- **Nesting:** pass a schema class, or a block (`field :address do ... end`).
- **Free-form data** needs `:json`. A bare `:object` without a schema is a definition error.
- **Strict input:** `reject_unknown!` makes unknown input keys a 422 instead of silently dropping them.

## Responses

```json
{ "data": { "id": 1, "number": "INV-1" } }
{ "data": [ ... ], "meta": { "limit": 25, "next_cursor": "WzI1XQ" } }
{ "error": { "code": "validation_failed", "message": "Some fields are invalid.",
             "details": { "items[0].quantity": ["must be at least 1"] }, "request_id": "..." } }
```

## Testing

Whoosh classes are Rack apps, so Rails request specs and `Rack::Test` work as they are:

```ruby
get "/api/v1/orders", headers: { "Authorization" => "Bearer #{token}" }
post "/api/v1/orders", params: { customer_id: 1, items: [] }, headers: headers, as: :json
```

Rate limits and idempotency keys are kept in one store for the whole process. In Rails, Whoosh clears it before every RSpec example and every `ActiveSupport::TestCase` test. Anywhere else, do it yourself:

```ruby
Whoosh.config.store.clear
```

## Logging

With `config.logger` set (Rails sets it to `Rails.logger`), every request logs one line at info level:

```
[whoosh] GET /api/v1/orders 200 in 3.4ms request_id=21fc1a84-8a6f-43f2-a5cd-742a7abfdd3d
```

The query string is left out, because it can carry secrets. Unexpected errors are logged with their backtrace.

## OpenAPI

`OrdersApi.openapi` returns an OpenAPI 3.1 document built from the same schemas. Set `config.openapi = true` (or `:authenticated`) to serve it at `/openapi.json`. It's off by default.

## Performance

The full pipeline runs in about **30 µs** for a single record with auth, rate limiting, param validation and serialization, and about **140 µs** for 25 records, measured in-process on Ruby 3.3 (`rake bench`). Routes compile into a segment tree at boot. Schemas are plain Ruby objects with no per-request metaprogramming. JSON goes through Oj when available. In a real app, database time dominates.

## Development

```sh
bundle install
bundle exec rake test
bundle exec rake bench
bundle exec rackup examples/config.ru
```

## License

MIT
