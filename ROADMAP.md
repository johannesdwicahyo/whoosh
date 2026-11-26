# Roadmap

Whoosh is one idea: a JSON API endpoint that can't boot without saying who may call it, what it accepts and what it returns. Everything here serves that idea, shipping it quickly, or keeping it fast.

## Rules for every release

- **Speed budget.** `rake bench` with YJIT stays under 10 µs for a single record and 30 µs for 25 records (today: 7.5 and 26). A change that breaks the budget doesn't merge.
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
- [ ] CI has never run: the GitHub account is locked on billing

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

- [ ] Mount it in one production Rails app and move a real set of endpoints over
- [ ] HTTP-level benchmark against Grape and a plain Rails API controller (same endpoint, same Puma), with the script in `bench/` so anyone can rerun it
- [ ] Run `rake bench` in CI against the speed budget

## 2.2.0: make it easy to adopt

- [ ] `bin/rails g whoosh:api Orders` scaffolds an API class, a schema and a test
- [ ] Test helpers for request specs (RSpec and Minitest)
- [ ] A launch post built around the demo: delete `authorize`, the app refuses to boot

## Later, only when someone asks

- Sliding-window rate limits
- Multipart file uploads
- Webhook signature verification
- Streaming responses

## Not doing

LLM helpers, MCP, background jobs, websockets, caching layers, an ORM, a CLI server. Whoosh 1.x tried to be all of these and was nobody's first choice for any of them. Use Rails, Sidekiq and the libraries you already have.
