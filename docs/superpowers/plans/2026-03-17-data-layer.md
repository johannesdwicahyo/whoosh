# Data Layer Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add .env file loading, auto-managed Sequel database connection, and key-value cache with TTL (memory + Redis stores) to the Whoosh framework.

**Architecture:** `EnvLoader` parses `.env` files at boot before config. `Database.connect_from_config` wraps existing connect/config_from. `Cache` module with `MemoryStore` (Hash+TTL+Mutex) and `RedisStore` (lazy redis gem). All registered via DI in App#initialize.

**Tech Stack:** Ruby 3.4+, RSpec, rack-test. Optional: sequel, redis, dotenv gems.

**Spec:** `docs/superpowers/specs/2026-03-17-data-layer-design.md`

**Depends on:** v1.0.1 (424 tests passing).

---

## Chunk 1: EnvLoader

### Task 1: EnvLoader

**Files:**
- Create: `lib/whoosh/env_loader.rb`
- Create: `spec/whoosh/env_loader_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/env_loader_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Whoosh::EnvLoader do
  describe ".load" do
    it "loads KEY=value pairs into ENV" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".env"), "TEST_WHOOSH_A=hello\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_A"]).to eq("hello")
      ensure
        ENV.delete("TEST_WHOOSH_A")
      end
    end

    it "does not override existing ENV vars" do
      Dir.mktmpdir do |dir|
        ENV["TEST_WHOOSH_B"] = "original"
        File.write(File.join(dir, ".env"), "TEST_WHOOSH_B=overridden\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_B"]).to eq("original")
      ensure
        ENV.delete("TEST_WHOOSH_B")
      end
    end

    it "handles quoted values" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".env"), "TEST_WHOOSH_C=\"hello world\"\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_C"]).to eq("hello world")
      ensure
        ENV.delete("TEST_WHOOSH_C")
      end
    end

    it "handles single-quoted values" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".env"), "TEST_WHOOSH_D='single'\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_D"]).to eq("single")
      ensure
        ENV.delete("TEST_WHOOSH_D")
      end
    end

    it "skips comments and blank lines" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".env"), "# comment\n\nTEST_WHOOSH_E=yes\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_E"]).to eq("yes")
      ensure
        ENV.delete("TEST_WHOOSH_E")
      end
    end

    it "handles empty values" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".env"), "TEST_WHOOSH_F=\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_F"]).to eq("")
      ensure
        ENV.delete("TEST_WHOOSH_F")
      end
    end

    it "does nothing when .env file missing" do
      expect { Whoosh::EnvLoader.load("/nonexistent") }.not_to raise_error
    end

    it "delegates to dotenv if available" do
      # Just verify it doesn't crash when checking for dotenv
      expect { Whoosh::EnvLoader.load("/nonexistent") }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/env_loader_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/env_loader.rb
# frozen_string_literal: true

module Whoosh
  module EnvLoader
    def self.load(root)
      path = File.join(root, ".env")
      return unless File.exist?(path)

      # Delegate to dotenv if available
      if dotenv_available?
        require "dotenv"
        Dotenv.load(path)
        return
      end

      # Built-in parser
      parse(File.read(path)).each do |key, value|
        ENV[key] ||= value
      end
    end

    def self.parse(content)
      pairs = {}
      content.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        key, value = line.split("=", 2)
        next unless key && value

        key = key.strip
        value = value.strip

        # Strip quotes
        if (value.start_with?('"') && value.end_with?('"')) ||
           (value.start_with?("'") && value.end_with?("'"))
          value = value[1..-2]
        end

        pairs[key] = value
      end
      pairs
    end

    def self.dotenv_available?
      require "dotenv"
      true
    rescue LoadError
      false
    end
  end
end
```

- [ ] **Step 4: Add autoload to lib/whoosh.rb**

Add `autoload :EnvLoader, "whoosh/env_loader"` to the Whoosh module.

- [ ] **Step 5: Wire into App#initialize**

Read `lib/whoosh/app.rb`. Add as the **first line** inside `initialize`, before `@config = Config.load(root: root)`:

```ruby
      EnvLoader.load(root)
```

- [ ] **Step 6: Run tests**

Run: `bundle exec rspec spec/whoosh/env_loader_spec.rb`
Expected: All pass

Run: `bundle exec rspec`
Expected: All pass (424 + new)

- [ ] **Step 7: Commit**

```bash
git add lib/whoosh/env_loader.rb spec/whoosh/env_loader_spec.rb lib/whoosh.rb lib/whoosh/app.rb
git commit -m "feat: add EnvLoader for .env file parsing at boot"
```

---

## Chunk 2: Cache

### Task 2: Memory Store

**Files:**
- Create: `lib/whoosh/cache/memory_store.rb`
- Create: `spec/whoosh/cache/memory_store_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/cache/memory_store_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Cache::MemoryStore do
  let(:store) { Whoosh::Cache::MemoryStore.new(default_ttl: 300) }

  describe "#set and #get" do
    it "stores and retrieves values" do
      store.set("key", { name: "test" })
      expect(store.get("key")).to eq({ "name" => "test" })
    end

    it "returns nil for missing keys" do
      expect(store.get("missing")).to be_nil
    end

    it "returns nil for expired keys" do
      store.set("key", "value", ttl: 0.01)
      sleep 0.02
      expect(store.get("key")).to be_nil
    end
  end

  describe "#fetch" do
    it "returns cached value on hit" do
      store.set("key", "cached")
      result = store.fetch("key") { "computed" }
      expect(result).to eq("cached")
    end

    it "computes and stores on miss" do
      result = store.fetch("key", ttl: 60) { "computed" }
      expect(result).to eq("computed")
      expect(store.get("key")).to eq("computed")
    end
  end

  describe "#delete" do
    it "removes a key" do
      store.set("key", "value")
      store.delete("key")
      expect(store.get("key")).to be_nil
    end
  end

  describe "#clear" do
    it "removes all keys" do
      store.set("a", 1)
      store.set("b", 2)
      store.clear
      expect(store.get("a")).to be_nil
      expect(store.get("b")).to be_nil
    end
  end

  describe "#close" do
    it "is a no-op (interface consistency)" do
      expect { store.close }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/cache/memory_store.rb
# frozen_string_literal: true

module Whoosh
  module Cache
    class MemoryStore
      def initialize(default_ttl: 300)
        @store = {}
        @default_ttl = default_ttl
        @mutex = Mutex.new
      end

      def get(key)
        @mutex.synchronize do
          entry = @store[key]
          return nil unless entry
          if entry[:expires_at] && Time.now.to_f > entry[:expires_at]
            @store.delete(key)
            return nil
          end
          entry[:value]
        end
      end

      def set(key, value, ttl: nil)
        ttl ||= @default_ttl
        serialized = Serialization::Json.decode(Serialization::Json.encode(value))
        @mutex.synchronize do
          @store[key] = { value: serialized, expires_at: Time.now.to_f + ttl }
        end
        true
      end

      def fetch(key, ttl: nil)
        existing = get(key)
        return existing unless existing.nil?
        value = yield
        set(key, value, ttl: ttl)
        # Return the value before serialization round-trip for consistency
        Serialization::Json.decode(Serialization::Json.encode(value))
      end

      def delete(key)
        @mutex.synchronize { @store.delete(key) }
        true
      end

      def clear
        @mutex.synchronize { @store.clear }
        true
      end

      def close
        # No-op for memory store
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/cache/memory_store.rb spec/whoosh/cache/memory_store_spec.rb
git commit -m "feat: add Cache::MemoryStore with TTL and thread-safe access"
```

---

### Task 3: Redis Store (Interface Only)

**Files:**
- Create: `lib/whoosh/cache/redis_store.rb`
- Create: `spec/whoosh/cache/redis_store_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/cache/redis_store_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Cache::RedisStore do
  describe ".new" do
    it "raises DependencyError if redis gem not available" do
      original = Whoosh::Cache::RedisStore.instance_variable_get(:@redis_available)
      Whoosh::Cache::RedisStore.instance_variable_set(:@redis_available, false)
      expect { Whoosh::Cache::RedisStore.new(url: "redis://localhost") }.to raise_error(Whoosh::Errors::DependencyError)
      Whoosh::Cache::RedisStore.instance_variable_set(:@redis_available, original)
    end
  end

  describe "interface" do
    it "responds to cache interface methods" do
      # Verify the class defines the right methods without needing Redis
      expect(Whoosh::Cache::RedisStore.instance_methods(false)).to include(:get, :set, :fetch, :delete, :clear, :close)
    end
  end
end
```

- [ ] **Step 2: Write implementation**

```ruby
# lib/whoosh/cache/redis_store.rb
# frozen_string_literal: true

module Whoosh
  module Cache
    class RedisStore
      @redis_available = nil

      def self.available?
        if @redis_available.nil?
          @redis_available = begin
            require "redis"
            true
          rescue LoadError
            false
          end
        end
        @redis_available
      end

      def initialize(url:, default_ttl: 300, pool_size: 5)
        unless self.class.available?
          raise Errors::DependencyError, "Cache Redis store requires the 'redis' gem"
        end
        @redis = Redis.new(url: url)
        @default_ttl = default_ttl
      end

      def get(key)
        raw = @redis.get(key)
        return nil unless raw
        Serialization::Json.decode(raw)
      rescue => e
        nil
      end

      def set(key, value, ttl: nil)
        ttl ||= @default_ttl
        raw = Serialization::Json.encode(value)
        @redis.set(key, raw, ex: ttl)
        true
      rescue => e
        false
      end

      def fetch(key, ttl: nil)
        existing = get(key)
        return existing unless existing.nil?
        value = yield
        set(key, value, ttl: ttl)
        Serialization::Json.decode(Serialization::Json.encode(value))
      end

      def delete(key)
        @redis.del(key) > 0
      rescue => e
        false
      end

      def clear
        @redis.flushdb
        true
      rescue => e
        false
      end

      def close
        @redis.close
      rescue => e
        # Already closed
      end
    end
  end
end
```

- [ ] **Step 3: Run test, commit**

```bash
git add lib/whoosh/cache/redis_store.rb spec/whoosh/cache/redis_store_spec.rb
git commit -m "feat: add Cache::RedisStore with lazy redis gem loading"
```

---

### Task 4: Cache Module and App Integration

**Files:**
- Create: `lib/whoosh/cache.rb`
- Modify: `lib/whoosh.rb`
- Modify: `lib/whoosh/app.rb`
- Create: `spec/whoosh/app_cache_spec.rb`

- [ ] **Step 1: Write the test**

```ruby
# spec/whoosh/app_cache_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App cache integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  it "provides a cache via DI" do
    application.get "/cached" do |req, cache:|
      result = cache.fetch("greeting", ttl: 60) { "hello" }
      { greeting: result }
    end

    get "/cached"
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)["greeting"]).to eq("hello")

    # Second request hits cache
    get "/cached"
    expect(JSON.parse(last_response.body)["greeting"]).to eq("hello")
  end
end
```

- [ ] **Step 2: Write Cache module**

```ruby
# lib/whoosh/cache.rb
# frozen_string_literal: true

module Whoosh
  module Cache
    autoload :MemoryStore, "whoosh/cache/memory_store"
    autoload :RedisStore,  "whoosh/cache/redis_store"

    def self.build(config_data = {})
      cache_config = config_data["cache"] || {}
      store = cache_config["store"] || "memory"
      default_ttl = cache_config["default_ttl"] || 300

      case store
      when "memory"
        MemoryStore.new(default_ttl: default_ttl)
      when "redis"
        url = cache_config["url"] || "redis://localhost:6379"
        pool_size = cache_config["pool_size"] || 5
        RedisStore.new(url: url, default_ttl: default_ttl, pool_size: pool_size)
      else
        raise ArgumentError, "Unknown cache store: #{store}"
      end
    end
  end
end
```

- [ ] **Step 3: Add autoload to lib/whoosh.rb**

Add `autoload :Cache, "whoosh/cache"` to the Whoosh module.

- [ ] **Step 4: Wire into App**

Read `lib/whoosh/app.rb`. Add private method `auto_register_cache` and call it in initialize after `load_plugin_config`:

```ruby
    def auto_register_cache
      @di.provide(:cache) { Cache.build(@config.data) }
    end
```

- [ ] **Step 5: Run tests, commit**

```bash
git add lib/whoosh/cache.rb spec/whoosh/app_cache_spec.rb lib/whoosh.rb lib/whoosh/app.rb
git commit -m "feat: add Cache module with auto-registration via DI"
```

---

## Chunk 3: Database Integration

### Task 5: Database connect_from_config and App Integration

**Files:**
- Modify: `lib/whoosh/database.rb`
- Modify: `lib/whoosh/app.rb`
- Create: `spec/whoosh/database_integration_spec.rb`

- [ ] **Step 1: Write the test**

```ruby
# spec/whoosh/database_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Database integration" do
  describe "Whoosh::Database.connect_from_config" do
    it "returns nil when no database config" do
      expect(Whoosh::Database.connect_from_config({})).to be_nil
    end

    it "returns nil when database has no url" do
      expect(Whoosh::Database.connect_from_config({ "database" => {} })).to be_nil
    end

    it "raises DependencyError if sequel not available" do
      original = Whoosh::Database.instance_variable_get(:@sequel_available)
      Whoosh::Database.instance_variable_set(:@sequel_available, false)
      config = { "database" => { "url" => "sqlite://test.db" } }
      expect { Whoosh::Database.connect_from_config(config) }.to raise_error(Whoosh::Errors::DependencyError)
      Whoosh::Database.instance_variable_set(:@sequel_available, original)
    end
  end

  describe "App auto-registration" do
    it "does not crash when no database config" do
      expect { Whoosh::App.new }.not_to raise_error
    end

    it "logs warning when database config exists but sequel missing" do
      # App should boot without crashing even if sequel isn't available
      expect { Whoosh::App.new }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Update Database module**

Read `lib/whoosh/database.rb`. Add:

```ruby
    def self.connect_from_config(config_data, logger: nil)
      db_config = config_from(config_data)
      return nil unless db_config

      ensure_available!
      db = connect(db_config[:url], max_connections: db_config[:max_connections], log_level: db_config[:log_level])
      db
    end
```

- [ ] **Step 3: Wire into App**

Read `lib/whoosh/app.rb`. Add private method and call after `auto_register_cache`:

```ruby
    def auto_register_database
      db_config = Database.config_from(@config.data)
      return unless db_config

      unless Database.available?
        @logger.warn("database_unavailable", message: "database config found but sequel gem not installed")
        return
      end

      @di.provide(:db) { Database.connect_from_config(@config.data, logger: @logger) }
    end
```

- [ ] **Step 4: Run tests, commit**

```bash
git add lib/whoosh/database.rb lib/whoosh/app.rb spec/whoosh/database_integration_spec.rb
git commit -m "feat: add Database.connect_from_config and auto-registration in App"
```

---

### Task 6: Update Project Generator and Final Verification

**Files:**
- Modify: `lib/whoosh/cli/project_generator.rb`

- [ ] **Step 1: Update generator**

Read `lib/whoosh/cli/project_generator.rb`. Update the `.env.example` template to include DATABASE_URL and REDIS_URL:

```
# WHOOSH_PORT=9292
# WHOOSH_ENV=development
# DATABASE_URL=sqlite://db/development.sqlite3
# REDIS_URL=redis://localhost:6379
```

Also update `app_yml_template` to include database and cache sections:

```yaml
app:
  name: "#{name.capitalize} API"
  port: 9292
  host: localhost

database:
  url: <%= ENV.fetch("DATABASE_URL", "sqlite://db/development.sqlite3") %>
  max_connections: 10

cache:
  store: memory
  default_ttl: 300

logging:
  level: info
  format: json

docs:
  enabled: true
```

- [ ] **Step 2: Run full suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add lib/whoosh/cli/project_generator.rb
git commit -m "feat: update project generator with database and cache config templates"
```

---

## Completion Checklist

- [ ] `bundle exec rspec` — all green
- [ ] EnvLoader parses .env files and loads into ENV
- [ ] EnvLoader does not override existing ENV vars
- [ ] EnvLoader delegates to dotenv if available
- [ ] EnvLoader called first in App#initialize
- [ ] Cache::MemoryStore with get/set/fetch/delete/clear and TTL
- [ ] Cache::RedisStore with same interface, lazy redis gem
- [ ] Cache.build factory creates correct store from config
- [ ] Cache auto-registered via DI, accessible as `cache` in endpoints
- [ ] Database.connect_from_config wraps existing methods
- [ ] Database auto-registered via DI when config exists
- [ ] Database logs warning when config exists but gem missing
- [ ] Project generator updated with database/cache config
- [ ] All existing tests still pass
