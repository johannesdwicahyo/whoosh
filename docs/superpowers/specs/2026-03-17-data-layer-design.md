# Whoosh Data Layer Design

**Date:** 2026-03-17
**Status:** Approved
**Scope:** .env loading, Database integration (Sequel), Cache layer (memory + Redis)

## Overview

Add the data persistence foundation that all other production features depend on. Three components: .env file loading at boot, auto-managed Sequel database connection, and a key-value cache with TTL support.

All three follow Whoosh's "works with zero deps, upgrade when ready" pattern.

## .env Loading

### Behavior

- Loads `.env` file from project root **at the very start of `App#initialize`**, before `Config.load`
- Sets values into `ENV` only if the key is not already set (real ENV always wins)
- Built-in parser handles: `KEY=value`, `KEY="quoted value"`, `# comments`, blank lines
- If `dotenv` gem is present, delegates to it instead of built-in parser
- Loaded before `Config.load` so database URLs etc. are available to YAML ERB

### Boot Order in App#initialize

```
1. EnvLoader.load(root)           # .env → ENV (first thing)
2. Config.load(root:)             # app.yml with ERB (can now read ENV)
3. Router, DI, Middleware, etc.   # existing setup
4. load_plugin_config             # plugins.yml
5. auto_register_database         # db from config (new)
6. auto_register_cache            # cache from config (new)
7. setup_default_middleware       # existing
```

### Precedence (highest to lowest)

1. Real environment variables
2. `.env` file
3. `config/app.yml`
4. Framework defaults

### Built-in Parser

Handles:
- `KEY=value` — simple assignment
- `KEY="value with spaces"` — double-quoted values
- `KEY='value'` — single-quoted values
- `# comment` — full-line comments
- Blank lines — ignored
- `KEY=` — empty value

Does NOT handle:
- Multiline values
- Variable interpolation (`$OTHER_VAR`)
- Export prefix (`export KEY=value`)

If these are needed, install `dotenv` gem.

### File Location

```
project_root/
├── .env              # loaded automatically
├── .env.example      # template (not loaded)
├── app.rb
```

## Database Integration

### Auto-Connection

When `database` section exists in `config/app.yml`, Whoosh auto-connects via Sequel and registers `db` as a DI singleton:

```yaml
# config/app.yml
database:
  url: <%= ENV.fetch("DATABASE_URL", "sqlite://db/development.sqlite3") %>
  max_connections: 10
  log_level: debug    # logs SQL queries when set to "debug"
```

Note: Uses `log_level` (not `log_queries`) to match existing `Database.connect` interface.

### Usage

```ruby
# Available as `db` in inline endpoints via DI kwargs:
app.post "/users" do |req, db:|
  id = db[:users].insert(name: req.body["name"])
  { id: id }
end
```

Note: Class-based endpoints currently do not receive DI-injected dependencies. This is a known limitation. Use `app.provide(:db)` and access via the app's DI container directly if needed in class-based endpoints. Fixing class-based DI injection is out of scope for this spec.

### Override

```ruby
# Developer can override auto-discovery:
app.provide(:db) { Sequel.connect(ENV["CUSTOM_DB_URL"]) }
```

### Lifecycle

- **Boot:** If `database` config exists and `sequel` gem is available, connect and register as `db` singleton via DI
- **Missing gem:** If config exists but `sequel` not installed, log a warning (don't crash)
- **No config:** No connection attempted, no warning
- **Shutdown:** Connection closed via existing `Shutdown` → `DI.close_all` (Sequel::Database responds to `#close`/`#disconnect`)
- **Query logging:** When `log_level: debug`, attach a logger to the Sequel connection

### Implementation

- Update `Whoosh::Database` with `connect_from_config(config_hash, logger: nil)` method that wraps existing `connect` and `config_from`:
  - Takes raw config data hash, extracts database section via `config_from`
  - Calls `connect(url, max_connections:, log_level:)` with extracted values
  - Returns the Sequel::Database instance
- In `App#initialize`, add `auto_register_database` private method called after plugin config
- Register via `@di.provide(:db) { Database.connect_from_config(@config.data, logger: @logger) }` — lazy singleton, only connects on first `db` access

## Cache Layer

### Interface

```ruby
cache.set("key", value, ttl: 120)     # store with TTL (uses default_ttl if omitted)
cache.get("key")                       # => value or nil
cache.fetch("key", ttl: 60) { compute } # get or compute+store
cache.delete("key")                    # remove, returns true/false
cache.clear                            # flush all
```

**Important:** Cache keys and values use string keys in hashes. Storing `{user_id: 1}` returns `{"user_id" => 1}` due to JSON serialization round-trip. Use string keys consistently.

### Configuration

```yaml
# config/app.yml (optional — works without config, defaults to memory store)
cache:
  store: memory       # memory | redis
  url: redis://localhost:6379   # only for redis store
  pool_size: 5        # Redis connection pool size (default: 5)
  default_ttl: 300    # seconds, default 5 minutes
```

### Memory Store

- `Hash`-based with TTL tracking via `{ value:, expires_at: }` entries
- Lazy expiry: expired entries removed on read, not by background sweeper
- Thread-safe via `Mutex`
- Good for single-process development
- Lost on restart
- Implements `#close` (no-op, for interface consistency)

### Redis Store

- Wraps `redis` gem (optional dependency, lazy-loaded)
- Uses `SET key value EX ttl` for TTL (not deprecated `SETEX`)
- Connection pool: uses `connection_pool` gem if available, otherwise single connection with Mutex
- Shared across processes, persists across restarts
- If `redis` gem not installed but config says `store: redis`, raise `DependencyError`
- Implements `#close` — calls `redis.close` to release the connection
- **Error handling for connection failures:** `get`/`fetch` return `nil`, `set` returns `false`, `delete`/`clear` return `false`. Errors are logged via app logger, never raised to the caller. Cache is best-effort — app must work without it.

### Value Serialization

- Values serialized with `Serialization::Json.encode` / `decode`
- Supports hashes, arrays, strings, numbers
- Complex objects (Time, BigDecimal) go through the existing `prepare` pipeline
- **Symbol keys are converted to strings** during JSON round-trip — documented behavior, not a bug

### App Integration

- Registered as `cache` via DI at boot as a singleton
- Available in inline endpoints via DI kwargs: `do |req, cache:| ... end`
- Store selected based on config, defaults to memory
- `RedisStore#close` called on shutdown via `DI.close_all`

## Files

### New Files

| File | Purpose |
|------|---------|
| `lib/whoosh/env_loader.rb` | .env file parser and loader |
| `lib/whoosh/cache.rb` | Cache module with store factory (`Cache.build(config)`) |
| `lib/whoosh/cache/memory_store.rb` | In-memory cache with TTL |
| `lib/whoosh/cache/redis_store.rb` | Redis-backed cache |
| `spec/whoosh/env_loader_spec.rb` | .env parser tests |
| `spec/whoosh/cache/memory_store_spec.rb` | Memory store tests |
| `spec/whoosh/cache/redis_store_spec.rb` | Redis store interface tests (no real Redis) |
| `spec/whoosh/database_integration_spec.rb` | DB auto-connect tests |

### Modified Files

| File | Change |
|------|--------|
| `lib/whoosh.rb` | Add autoloads for EnvLoader, Cache module |
| `lib/whoosh/app.rb` | Load .env first in initialize, auto-register db and cache |
| `lib/whoosh/database.rb` | Add `connect_from_config` method |
| `lib/whoosh/cli/project_generator.rb` | Include `.env.example` with DATABASE_URL |

## Dependencies

- No new hard dependencies
- `sequel` — optional, for database (already in plugin registry)
- `redis` — optional, for Redis cache store
- `dotenv` — optional, for advanced .env parsing
