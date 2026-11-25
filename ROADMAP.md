# Roadmap

Whoosh is one idea: a JSON API endpoint that can't boot without saying who may call it, what it accepts and what it returns. Everything here serves that idea, shipping it quickly, or keeping it fast.

## Rules for every release

- **Speed budget.** `rake bench` with YJIT stays under 10 µs for a single record and 30 µs for 25 records (today: 7.5 and 26). A change that breaks the budget doesn't merge.
- **No new runtime dependencies.** `bigdecimal` is the only one.
- **No per-request metaprogramming.** Everything is compiled when the class loads.
- **A feature is added when a real app needed it**, not before.

## 0.1.0: ship it

The goal is a gem people can install. Nothing new gets built.

- [x] Work with json 3.x (JSON bodies returned 500)
- [x] Work on Ruby 3.4+ (`bigdecimal` declared, `base64` no longer needed)
- [x] Cursor pagination on timestamps: encode times with full precision so `paginate :cursor, by: :created_at` can't skip or repeat rows, and add a test
- [x] Idempotency: a request that dies mid-flight holds its key for 24 hours; give the "processing" state a short lock (60 s)
- [x] CI: add Ruby 4.0 to the matrix, and one job on the newest json
- [ ] Fill in the gemspec email and homepage
- [x] README: add "Why not Grape, or Rails with rack-attack, Pundit and a serializer?"
- [ ] `git init`, publish the repository, push `whoosh` 0.1.0

### Reusing the name

`whoosh` 1.0.1 to 1.10.0 are on RubyGems (the old framework, 4,287 downloads in total). 0.1.0 was never published, so it can be pushed. But `gem "whoosh"` keeps resolving to 1.10.0 until the 1.x versions are yanked. Yanking can't be undone and breaks anyone who installs 1.x fresh, so it is the last step of the release, done deliberately.

## 0.2.0: prove it in a real app

- [ ] Mount it in one production Rails app and move a real set of endpoints over
- [ ] Fix whatever that hurts; this decides the rest of the list
- [ ] HTTP-level benchmark against Grape and a plain Rails API controller (same endpoint, same Puma), with the script in `bench/` so anyone can rerun it
- [ ] Run `rake bench` in CI against the speed budget

## 0.3.0: make it easy to adopt

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
