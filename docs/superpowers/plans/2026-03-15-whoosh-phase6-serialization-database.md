# Whoosh Phase 6: Serialization & Database Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MessagePack and Protobuf serializer interfaces (lazy-loaded, optional gems), extend the content Negotiator for multi-format support, update Response/Request for format-aware serialization, and add Sequel database integration with config support.

**Architecture:** Serializers (`Msgpack`, `Protobuf`) follow the same interface as `Json` (`.encode`, `.decode`, `.content_type`). The Negotiator maps Accept/Content-Type headers to the right serializer. `Database` module wraps Sequel connection with config from `app.yml`. Sequel adapter registered as plugin initializer in Registry.

**Tech Stack:** Ruby 3.4+, RSpec. Optional gems: `msgpack`, `google-protobuf`, `sequel`. None required at runtime — lazy loaded on use.

**Spec:** `docs/superpowers/specs/2026-03-11-whoosh-design.md` (Serialization lines 164-196, Database lines 780-867)

**Depends on:** Phase 1-5 complete (221 tests passing).

---

## Chunk 1: Serialization

### Task 1: MessagePack Serializer

**Files:**
- Create: `lib/whoosh/serialization/msgpack.rb`
- Test: `spec/whoosh/serialization/msgpack_spec.rb`

MessagePack is optional — the class lazy-requires the `msgpack` gem and raises `DependencyError` if unavailable.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/serialization/msgpack_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Serialization::Msgpack do
  describe ".content_type" do
    it "returns application/msgpack" do
      expect(Whoosh::Serialization::Msgpack.content_type).to eq("application/msgpack")
    end
  end

  describe ".available?" do
    it "returns true if msgpack gem is installed" do
      # May be true or false depending on environment
      expect(Whoosh::Serialization::Msgpack.available?).to be(true).or be(false)
    end
  end

  describe ".encode and .decode" do
    it "round-trips data if gem available" do
      skip "msgpack gem not installed" unless Whoosh::Serialization::Msgpack.available?
      data = { "name" => "test", "count" => 42 }
      encoded = Whoosh::Serialization::Msgpack.encode(data)
      expect(encoded).to be_a(String)
      decoded = Whoosh::Serialization::Msgpack.decode(encoded)
      expect(decoded["name"]).to eq("test")
      expect(decoded["count"]).to eq(42)
    end

    it "raises DependencyError if gem not available" do
      # Temporarily hide the gem
      original = Whoosh::Serialization::Msgpack.instance_variable_get(:@available)
      Whoosh::Serialization::Msgpack.instance_variable_set(:@available, false)
      expect { Whoosh::Serialization::Msgpack.encode({}) }.to raise_error(Whoosh::Errors::DependencyError)
      Whoosh::Serialization::Msgpack.instance_variable_set(:@available, original)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/serialization/msgpack_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/serialization/msgpack.rb
# frozen_string_literal: true

module Whoosh
  module Serialization
    class Msgpack
      @available = nil

      def self.available?
        if @available.nil?
          @available = begin
            require "msgpack"
            true
          rescue LoadError
            false
          end
        end
        @available
      end

      def self.content_type
        "application/msgpack"
      end

      def self.encode(data)
        ensure_available!
        MessagePack.pack(prepare(data))
      end

      def self.decode(raw)
        return nil if raw.nil? || raw.empty?
        ensure_available!
        MessagePack.unpack(raw)
      end

      def self.prepare(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_s).transform_values { |v| prepare(v) }
        when Array
          obj.map { |v| prepare(v) }
        when Symbol
          obj.to_s
        when Time, DateTime
          obj.iso8601
        when BigDecimal
          obj.to_s("F")
        else
          obj
        end
      end

      def self.ensure_available!
        raise Errors::DependencyError, "MessagePack requires the 'msgpack' gem" unless available?
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/serialization/msgpack_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/serialization/msgpack.rb spec/whoosh/serialization/msgpack_spec.rb
git commit -m "feat: add MessagePack serializer with lazy gem loading"
```

---

### Task 2: Protobuf Serializer

**Files:**
- Create: `lib/whoosh/serialization/protobuf.rb`
- Test: `spec/whoosh/serialization/protobuf_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/serialization/protobuf_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Serialization::Protobuf do
  describe ".content_type" do
    it "returns application/protobuf" do
      expect(Whoosh::Serialization::Protobuf.content_type).to eq("application/protobuf")
    end
  end

  describe ".available?" do
    it "returns a boolean" do
      expect(Whoosh::Serialization::Protobuf.available?).to be(true).or be(false)
    end
  end

  describe ".encode" do
    it "raises DependencyError if gem not available" do
      original = Whoosh::Serialization::Protobuf.instance_variable_get(:@available)
      Whoosh::Serialization::Protobuf.instance_variable_set(:@available, false)
      expect { Whoosh::Serialization::Protobuf.encode({}) }.to raise_error(Whoosh::Errors::DependencyError)
      Whoosh::Serialization::Protobuf.instance_variable_set(:@available, original)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/serialization/protobuf.rb
# frozen_string_literal: true

module Whoosh
  module Serialization
    class Protobuf
      @available = nil

      def self.available?
        if @available.nil?
          @available = begin
            require "google/protobuf"
            true
          rescue LoadError
            false
          end
        end
        @available
      end

      def self.content_type
        "application/protobuf"
      end

      def self.encode(data, message_class: nil)
        ensure_available!
        raise Errors::DependencyError, "Protobuf encoding requires a message_class" unless message_class
        msg = message_class.new(data)
        message_class.encode(msg)
      end

      def self.decode(raw, message_class: nil)
        return nil if raw.nil? || raw.empty?
        ensure_available!
        raise Errors::DependencyError, "Protobuf decoding requires a message_class" unless message_class
        message_class.decode(raw)
      end

      def self.ensure_available!
        raise Errors::DependencyError, "Protobuf requires the 'google-protobuf' gem" unless available?
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/serialization/protobuf.rb spec/whoosh/serialization/protobuf_spec.rb
git commit -m "feat: add Protobuf serializer interface with lazy gem loading"
```

---

### Task 3: Extend Negotiator and Add Autoloads

**Files:**
- Modify: `lib/whoosh/serialization/negotiator.rb`
- Modify: `lib/whoosh.rb` (add autoloads for Msgpack, Protobuf)
- Test: `spec/whoosh/serialization/negotiator_spec.rb` (update existing)

- [ ] **Step 1: Update the negotiator test**

Add these tests to the existing `spec/whoosh/serialization/negotiator_spec.rb`:

```ruby
  describe ".for_accept with msgpack" do
    it "returns Msgpack serializer for application/msgpack" do
      serializer = Whoosh::Serialization::Negotiator.for_accept("application/msgpack")
      expect(serializer).to eq(Whoosh::Serialization::Msgpack)
    end
  end

  describe ".for_accept with protobuf" do
    it "returns Protobuf serializer for application/protobuf" do
      serializer = Whoosh::Serialization::Negotiator.for_accept("application/protobuf")
      expect(serializer).to eq(Whoosh::Serialization::Protobuf)
    end
  end

  describe ".for_content_type with msgpack" do
    it "returns Msgpack for application/msgpack" do
      deserializer = Whoosh::Serialization::Negotiator.for_content_type("application/msgpack")
      expect(deserializer).to eq(Whoosh::Serialization::Msgpack)
    end
  end
```

- [ ] **Step 2: Run test to verify new tests fail**

- [ ] **Step 3: Update Negotiator**

Read `lib/whoosh/serialization/negotiator.rb` first. Update the `SERIALIZERS` constant:

```ruby
      SERIALIZERS = {
        "application/json" => -> { Json },
        "application/msgpack" => -> { Msgpack },
        "application/x-msgpack" => -> { Msgpack },
        "application/protobuf" => -> { Protobuf },
        "application/x-protobuf" => -> { Protobuf }
      }.freeze
```

- [ ] **Step 4: Add autoloads to lib/whoosh.rb**

Add inside the `module Serialization` block:

```ruby
    autoload :Msgpack,    "whoosh/serialization/msgpack"
    autoload :Protobuf,   "whoosh/serialization/protobuf"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/whoosh/serialization/`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/whoosh/serialization/negotiator.rb lib/whoosh.rb spec/whoosh/serialization/negotiator_spec.rb
git commit -m "feat: extend Negotiator with MessagePack and Protobuf support"
```

---

## Chunk 2: Database

### Task 4: Database Module

**Files:**
- Create: `lib/whoosh/database.rb`
- Test: `spec/whoosh/database_spec.rb`

The Database module wraps Sequel connection setup. It reads config from `app.yml` database section and provides a connection accessor.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/database_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Database do
  describe ".connect" do
    it "raises DependencyError if sequel gem not available" do
      original = Whoosh::Database.instance_variable_get(:@sequel_available)
      Whoosh::Database.instance_variable_set(:@sequel_available, false)
      expect { Whoosh::Database.connect("sqlite://test.db") }.to raise_error(Whoosh::Errors::DependencyError)
      Whoosh::Database.instance_variable_set(:@sequel_available, original)
    end
  end

  describe ".config_from" do
    it "extracts database config from app config" do
      config_data = { "database" => { "url" => "sqlite://db/dev.sqlite3", "max_connections" => 5 } }
      result = Whoosh::Database.config_from(config_data)
      expect(result[:url]).to eq("sqlite://db/dev.sqlite3")
      expect(result[:max_connections]).to eq(5)
    end

    it "returns nil when no database config" do
      expect(Whoosh::Database.config_from({})).to be_nil
    end
  end

  describe ".available?" do
    it "returns a boolean" do
      expect(Whoosh::Database.available?).to be(true).or be(false)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/database.rb
# frozen_string_literal: true

module Whoosh
  class Database
    @sequel_available = nil

    def self.available?
      if @sequel_available.nil?
        @sequel_available = begin
          require "sequel"
          true
        rescue LoadError
          false
        end
      end
      @sequel_available
    end

    def self.connect(url, max_connections: 10, log_level: nil)
      ensure_available!
      db = Sequel.connect(url, max_connections: max_connections)
      db.loggers << ::Logger.new($stdout) if log_level == "debug"
      db
    end

    def self.config_from(config_data)
      db_config = config_data["database"]
      return nil unless db_config && db_config["url"]

      {
        url: db_config["url"],
        max_connections: db_config["max_connections"] || 10,
        log_level: db_config["log_level"]
      }
    end

    def self.ensure_available!
      raise Errors::DependencyError, "Database requires the 'sequel' gem" unless available?
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Add autoload to lib/whoosh.rb**

Add `autoload :Database, "whoosh/database"` to the main Whoosh module.

- [ ] **Step 6: Commit**

```bash
git add lib/whoosh/database.rb spec/whoosh/database_spec.rb lib/whoosh.rb
git commit -m "feat: add Database module with Sequel connection and config support"
```

---

### Task 5: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 2: Smoke test**

```bash
bundle exec ruby -e "
require 'whoosh'

# Test serialization negotiation
puts 'JSON: ' + Whoosh::Serialization::Negotiator.for_accept('application/json').to_s
puts 'MsgPack: ' + Whoosh::Serialization::Negotiator.for_accept('application/msgpack').to_s
puts 'Protobuf: ' + Whoosh::Serialization::Negotiator.for_accept('application/protobuf').to_s
puts 'Default: ' + Whoosh::Serialization::Negotiator.for_accept(nil).to_s

# Test msgpack availability
puts 'MsgPack available: ' + Whoosh::Serialization::Msgpack.available?.to_s

# Test protobuf availability
puts 'Protobuf available: ' + Whoosh::Serialization::Protobuf.available?.to_s

# Test database availability
puts 'Sequel available: ' + Whoosh::Database.available?.to_s

# Test database config extraction
config = Whoosh::Database.config_from({ 'database' => { 'url' => 'sqlite://db/dev.sqlite3' } })
puts 'DB config: ' + config.inspect

puts 'Phase 6 working!'
"
```

---

## Phase 6 Completion Checklist

- [ ] `bundle exec rspec` — all green
- [ ] MessagePack serializer with lazy gem loading
- [ ] Protobuf serializer interface with lazy gem loading
- [ ] Negotiator extended for msgpack and protobuf content types
- [ ] Autoloads added for Msgpack, Protobuf, Database
- [ ] Database module with Sequel connect and config extraction
- [ ] All Phase 1-5 tests still pass

## Next Phase

After Phase 6, proceed to **Phase 7: OpenAPI & Docs**.
