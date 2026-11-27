# Roadmap

Whoosh is one idea: a JSON API endpoint that can't boot without saying who may call it, what it accepts and what it returns. Everything here serves that idea, shipping it quickly, or keeping it fast.

## Rules for every release

- **Speed budget.** `BENCH_BUDGET=10,30 rake bench` with YJIT stays under 10 µs for a single record and 30 µs for 25 records (today: 7.5 and 26). A change that breaks the budget doesn't merge.
- **No new runtime dependencies.** `bigdecimal` is the only one.
- **No per-request metaprogramming.** Everything is compiled when the class loads.
- **A feature is added when a real app needed it**, not before.

## 2.0.0: ship it

The goal is a gem people can install. Nothing new gets built.

- [x] Work with json 3.x (JSON bodies returned 500)
- [x] Work on Ruby 3.4+ (`bigdecimal` declared, `base64` no longer needed)
- [x] Cursor pagination on timestamps: encode times with full precision so `paginate :cursor, by: :created_at` can't skip or repeat rows, and add a test
- [x] Idempotency: a request that dies mid-flight holds its key for 24 hours; give the "processing" state a short lock (60 s)
- [x] CI: add Ruby 4.0 to the matrix, and one job on the newest json
- [x] Gemspec homepage set to the existing repository; no public email, same as 1.x
- [x] README: add "Why not Grape, or Rails with rack-attack, Pundit and a serializer?"
- [x] `git init` and first commit
- [x] Keep the 1.x history on a `1.x` branch and push this history as the new `main`
- [x] `gem push` 2.0.0
- [x] Tested locally on Ruby 3.2, 3.3, 3.4 and 4.0 (as of 2.0.1)
- [x] CI runs: green on Ruby 3.2, 3.3, 3.4 and 4.0 since 2026-11-26

### Why 2.0.0 and not 0.1.0

`whoosh` 1.0.1 to 1.10.0 are the old framework. RubyGems doesn't allow yanking versions older than 30 days, so they stay for good, and anything numbered below them would never be what `gem install whoosh` gives you. The rewrite was first pushed as 0.1.0 and is re-released as 2.0.0 for that reason.

## 2.0.x: prove it in a new app

Fixes only, so these go out as patch releases.

- [x] Build a throwaway Rails app on PostgreSQL with the published gem (`../whoosh-wibawa-demo`, findings in its `FINDINGS.md`)
- [x] Cursor pagination on timestamps holds against a real database
- [x] Testing: rate limits and idempotency keys no longer leak between tests in Rails; the reset is documented for everything else
- [x] Log one line per request with status and duration
- [x] README: show a helper method for a repeated `authorize` rule, and say that every API class must be listed in the mount line
- [x] `gem push` 2.0.1
- [x] Decimals keep their scale with `scale:` on the field (`"2000.50"`, not `"2000.5"`)
- [x] `gem push` 2.0.2

## 2.1.0: prove it in a production app

- [x] Mount it in a real Rails app. The app is TapSale, a POS with an iPad client: its four catalog reads (categories, products, one product, modifier groups) are Whoosh endpoints on the live server since 2026-11-27, next to Rails controllers that keep the writes
- [ ] See a signed-in request go through it in production. So far only unauthenticated requests have been checked on the server; the first real one comes when an iPad build made after the move refreshes its catalog
- [ ] Move the order and payment endpoints, which are still Rails controllers
- [x] Errors as RFC 9457 problem details (`config.error_format = :problem`), which TapSale's iOS client already decodes
- [x] HTTP-level benchmark against Grape and a plain Rails API controller (same endpoint, same Puma): `rake bench:http`, results in the README
- [x] Run `rake bench` in CI against the speed budget (40 and 120 µs there: GitHub runners measured 25 and 81 µs, about 3.3 times slower than a developer machine)

### What the move to TapSale showed

It took one class and five schemas, and removed more code than it added. These are the places where Whoosh did not fit as it is:

- **One response shape per endpoint.** The old endpoint returned a short or a full product depending on `?include=full`. `returns` takes one schema, so the endpoint now always returns the full shape. Fine here; a real limit for an API that needs both
- **A 409 cannot carry a body.** TapSale answers a stale order update with 409 and the current order, so the app can show what changed. Fixed in 2.4.0: `conflict!(message, extra: { order: ... })`
- **Idempotency by a stored key.** The iPad replays queued orders days later with a `client_uuid` kept in the database. Whoosh's `Idempotency-Key` lives in a cache with a TTL, which is a different thing; TapSale keeps its own
- **401 says less.** The controllers answered "token expired" or "invalid token"; `authenticate` returns a user or nil, so Whoosh can only say "Sign in or send a valid token."
- **Mounting beside controllers** on the same paths needs a route constraint in the app (GET to Whoosh, the rest to Rails). It works, and the README does not mention it

## 2.2.0: make it easy to adopt

- [x] `bin/rails g whoosh:api Orders` scaffolds an API class, a schema and a test
- [x] Test helpers for request specs (RSpec and Minitest): `api_sign_in`
- [ ] A launch post built around the demo: delete `authorize`, the app refuses to boot (reviewed draft in `docs/launch-post.md`, not published)

## Later, only when someone asks

- Sliding-window rate limits
- Multipart file uploads
- Webhook signature verification (TapSale's App Store webhook is the first real case)
- A reason on a failed `authenticate`, if a client needs to tell an expired token from a bad one
- Streaming responses

## Not doing

LLM helpers, MCP, background jobs, websockets, caching layers, an ORM, a CLI server. Whoosh 1.x tried to be all of these and was nobody's first choice for any of them. Use Rails, Sidekiq and the libraries you already have.
