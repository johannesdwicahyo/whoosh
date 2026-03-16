# Whoosh Phase 3: Auth & Security Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add authentication (API key, JWT), rate limiting (in-memory with tiers and fail-open/fail-closed), token usage tracking, and per-key model access control — all with App DSL integration and middleware support.

**Architecture:** Auth strategies are standalone classes under `Whoosh::Auth::` that can be composed. `RateLimiter` uses an in-memory store (thread-safe via Mutex) with per-endpoint rules and tier support. `TokenTracker` is callback-based for billing hooks. `AccessControl` maps roles to allowed models. The App exposes `auth`, `rate_limit`, `token_tracking`, and `access_control` DSL blocks, and auth middleware can be applied to route groups.

**Tech Stack:** Ruby 3.4+, RSpec, rack-test. JWT requires optional `jwt` gem. No Redis dependency in Phase 3 (in-memory store only; Redis adapter deferred).

**Spec:** `docs/superpowers/specs/2026-03-11-whoosh-design.md` (Auth section, lines 298-342)

**Depends on:** Phase 1-2 complete (139 tests passing). Error classes `UnauthorizedError`, `ForbiddenError`, `RateLimitExceeded` already exist.

---

## Chunk 1: Auth Strategies

### Task 1: API Key Authentication

**Files:**
- Create: `lib/whoosh/auth/api_key.rb`
- Test: `spec/whoosh/auth/api_key_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/auth/api_key_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::ApiKey do
  describe "#authenticate" do
    it "returns the key when valid" do
      auth = Whoosh::Auth::ApiKey.new(
        keys: { "sk-test-123" => { role: :standard } },
        header: "X-API-Key"
      )

      env = Rack::MockRequest.env_for("/test", "HTTP_X_API_KEY" => "sk-test-123")
      request = Whoosh::Request.new(env)

      result = auth.authenticate(request)
      expect(result).to eq({ key: "sk-test-123", role: :standard })
    end

    it "raises UnauthorizedError when key is missing" do
      auth = Whoosh::Auth::ApiKey.new(
        keys: { "sk-test-123" => { role: :standard } },
        header: "X-API-Key"
      )

      env = Rack::MockRequest.env_for("/test")
      request = Whoosh::Request.new(env)

      expect { auth.authenticate(request) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end

    it "raises UnauthorizedError when key is invalid" do
      auth = Whoosh::Auth::ApiKey.new(
        keys: { "sk-test-123" => { role: :standard } },
        header: "X-API-Key"
      )

      env = Rack::MockRequest.env_for("/test", "HTTP_X_API_KEY" => "sk-bad")
      request = Whoosh::Request.new(env)

      expect { auth.authenticate(request) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end

    it "supports custom header names" do
      auth = Whoosh::Auth::ApiKey.new(
        keys: { "my-key" => { role: :admin } },
        header: "Authorization"
      )

      env = Rack::MockRequest.env_for("/test", "HTTP_AUTHORIZATION" => "Bearer my-key")
      request = Whoosh::Request.new(env)

      result = auth.authenticate(request)
      expect(result[:key]).to eq("my-key")
    end
  end

  describe "#register_key" do
    it "adds a key at runtime" do
      auth = Whoosh::Auth::ApiKey.new(keys: {})
      auth.register_key("sk-new", role: :basic)

      env = Rack::MockRequest.env_for("/test", "HTTP_X_API_KEY" => "sk-new")
      request = Whoosh::Request.new(env)

      result = auth.authenticate(request)
      expect(result[:role]).to eq(:basic)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/auth/api_key_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/auth/api_key.rb
# frozen_string_literal: true

module Whoosh
  module Auth
    class ApiKey
      def initialize(keys: {}, header: "X-API-Key")
        @keys = keys.dup
        @header = header
        @mutex = Mutex.new
      end

      def authenticate(request)
        raw_value = request.headers[@header]
        raise Errors::UnauthorizedError, "Missing API key" unless raw_value

        # Strip "Bearer " prefix if present
        key = raw_value.sub(/\ABearer\s+/i, "")

        metadata = @keys[key]
        raise Errors::UnauthorizedError, "Invalid API key" unless metadata

        { key: key, **metadata }
      end

      def register_key(key, **metadata)
        @mutex.synchronize do
          @keys[key] = metadata
        end
      end

      def revoke_key(key)
        @mutex.synchronize do
          @keys.delete(key)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/auth/api_key_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/auth/api_key.rb spec/whoosh/auth/api_key_spec.rb
git commit -m "feat: add API key authentication with header extraction and key registry"
```

---

### Task 2: JWT Authentication

**Files:**
- Create: `lib/whoosh/auth/jwt.rb`
- Test: `spec/whoosh/auth/jwt_spec.rb`

JWT uses Ruby's `openssl` stdlib for HMAC-SHA256 verification (no external gem needed for HS256).

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/auth/jwt_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::Jwt do
  let(:secret) { "test-secret-key-32chars-long!!!!" }
  let(:auth) { Whoosh::Auth::Jwt.new(secret: secret, algorithm: :hs256) }

  describe "#generate" do
    it "generates a valid JWT token" do
      token = auth.generate(sub: "user-1", role: :standard)
      expect(token).to be_a(String)
      expect(token.split(".").length).to eq(3)
    end
  end

  describe "#authenticate" do
    it "validates and decodes a token" do
      token = auth.generate(sub: "user-1", role: :standard)

      env = Rack::MockRequest.env_for("/test", "HTTP_AUTHORIZATION" => "Bearer #{token}")
      request = Whoosh::Request.new(env)

      result = auth.authenticate(request)
      expect(result[:sub]).to eq("user-1")
      expect(result[:role]).to eq("standard")
    end

    it "raises UnauthorizedError for missing token" do
      env = Rack::MockRequest.env_for("/test")
      request = Whoosh::Request.new(env)

      expect { auth.authenticate(request) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end

    it "raises UnauthorizedError for invalid token" do
      env = Rack::MockRequest.env_for("/test", "HTTP_AUTHORIZATION" => "Bearer invalid.token.here")
      request = Whoosh::Request.new(env)

      expect { auth.authenticate(request) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end

    it "raises UnauthorizedError for expired token" do
      auth_with_expiry = Whoosh::Auth::Jwt.new(secret: secret, algorithm: :hs256, expiry: -1)
      token = auth_with_expiry.generate(sub: "user-1")

      env = Rack::MockRequest.env_for("/test", "HTTP_AUTHORIZATION" => "Bearer #{token}")
      request = Whoosh::Request.new(env)

      expect { auth_with_expiry.authenticate(request) }.to raise_error(Whoosh::Errors::UnauthorizedError, /expired/i)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/auth/jwt_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/auth/jwt.rb
# frozen_string_literal: true

require "openssl"
require "base64"
require "json"

module Whoosh
  module Auth
    class Jwt
      def initialize(secret:, algorithm: :hs256, expiry: 3600)
        @secret = secret
        @algorithm = algorithm
        @expiry = expiry
      end

      def generate(sub:, **claims)
        header = { alg: "HS256", typ: "JWT" }
        now = Time.now.to_i
        payload = { sub: sub, iat: now, exp: now + @expiry }.merge(claims)

        header_b64 = base64url_encode(JSON.generate(header))
        payload_b64 = base64url_encode(JSON.generate(payload))
        signature = sign("#{header_b64}.#{payload_b64}")

        "#{header_b64}.#{payload_b64}.#{signature}"
      end

      def authenticate(request)
        auth_header = request.headers["Authorization"]
        raise Errors::UnauthorizedError, "Missing authorization header" unless auth_header

        token = auth_header.sub(/\ABearer\s+/i, "")
        decode(token)
      end

      private

      def decode(token)
        parts = token.split(".")
        raise Errors::UnauthorizedError, "Invalid token format" unless parts.length == 3

        header_b64, payload_b64, signature = parts

        # Verify signature
        expected_sig = sign("#{header_b64}.#{payload_b64}")
        unless secure_compare(signature, expected_sig)
          raise Errors::UnauthorizedError, "Invalid token signature"
        end

        # Decode payload
        payload = JSON.parse(base64url_decode(payload_b64))

        # Check expiry
        if payload["exp"] && payload["exp"] < Time.now.to_i
          raise Errors::UnauthorizedError, "Token expired"
        end

        payload.transform_keys(&:to_sym)
      rescue JSON::ParserError
        raise Errors::UnauthorizedError, "Invalid token payload"
      end

      def sign(data)
        digest = OpenSSL::Digest.new("SHA256")
        base64url_encode(OpenSSL::HMAC.digest(digest, @secret, data))
      end

      def base64url_encode(data)
        data = [data].pack("m0") if data.is_a?(String) && data.encoding == Encoding::BINARY || !data.is_a?(String)
        # Handle both binary and string data
        if data.is_a?(String) && !data.ascii_only?
          Base64.urlsafe_encode64(data, padding: false)
        else
          Base64.urlsafe_encode64(data.is_a?(String) ? data : data.to_s, padding: false)
        end
      end

      def base64url_decode(str)
        Base64.urlsafe_decode64(str)
      end

      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        l = a.unpack("C*")
        r = b.unpack("C*")
        result = 0
        l.zip(r) { |x, y| result |= x ^ y }
        result.zero?
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/auth/jwt_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/auth/jwt.rb spec/whoosh/auth/jwt_spec.rb
git commit -m "feat: add JWT authentication with HS256 signing and expiry validation"
```

---

## Chunk 2: Rate Limiting & Token Tracking

### Task 3: Rate Limiter

**Files:**
- Create: `lib/whoosh/auth/rate_limiter.rb`
- Test: `spec/whoosh/auth/rate_limiter_spec.rb`

In-memory rate limiter with per-endpoint rules, tier support, and fail-open/fail-closed.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/auth/rate_limiter_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::RateLimiter do
  describe "#check!" do
    it "allows requests under the limit" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 5, default_period: 60)
      expect { limiter.check!("key-1", "/test") }.not_to raise_error
    end

    it "raises RateLimitExceeded when over limit" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 2, default_period: 60)
      2.times { limiter.check!("key-1", "/test") }

      expect { limiter.check!("key-1", "/test") }.to raise_error(Whoosh::Errors::RateLimitExceeded)
    end

    it "tracks limits per key independently" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 2, default_period: 60)
      2.times { limiter.check!("key-1", "/test") }

      expect { limiter.check!("key-2", "/test") }.not_to raise_error
    end
  end

  describe "per-endpoint rules" do
    it "applies endpoint-specific limits" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 100, default_period: 60)
      limiter.rule("/chat", limit: 2, period: 60)

      2.times { limiter.check!("key-1", "/chat") }
      expect { limiter.check!("key-1", "/chat") }.to raise_error(Whoosh::Errors::RateLimitExceeded)

      # Default limit still applies to other endpoints
      expect { limiter.check!("key-1", "/other") }.not_to raise_error
    end
  end

  describe "tier support" do
    it "applies tier-based limits" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 10, default_period: 60)
      limiter.tier(:free, limit: 2, period: 60)
      limiter.tier(:pro, limit: 100, period: 60)
      limiter.tier(:enterprise, unlimited: true)

      2.times { limiter.check!("key-1", "/test", tier: :free) }
      expect { limiter.check!("key-1", "/test", tier: :free) }.to raise_error(Whoosh::Errors::RateLimitExceeded)

      # Enterprise tier is unlimited
      200.times { limiter.check!("key-2", "/test", tier: :enterprise) }
    end
  end

  describe "fail-open/fail-closed" do
    it "defaults to fail-open" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 5, default_period: 60, on_store_failure: :fail_open)
      # Simulate store failure by corrupting internal state
      limiter.instance_variable_set(:@store, nil)
      expect { limiter.check!("key-1", "/test") }.not_to raise_error
    end

    it "denies on fail-closed" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 5, default_period: 60, on_store_failure: :fail_closed)
      limiter.instance_variable_set(:@store, nil)
      expect { limiter.check!("key-1", "/test") }.to raise_error(Whoosh::Errors::RateLimitExceeded)
    end
  end

  describe "#remaining" do
    it "returns remaining requests for a key" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 5, default_period: 60)
      3.times { limiter.check!("key-1", "/test") }
      expect(limiter.remaining("key-1", "/test")).to eq(2)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/auth/rate_limiter_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/auth/rate_limiter.rb
# frozen_string_literal: true

module Whoosh
  module Auth
    class RateLimiter
      def initialize(default_limit: 60, default_period: 60, on_store_failure: :fail_open)
        @default_limit = default_limit
        @default_period = default_period
        @on_store_failure = on_store_failure
        @rules = {}
        @tiers = {}
        @store = {}
        @mutex = Mutex.new
      end

      def rule(path, limit:, period:)
        @rules[path] = { limit: limit, period: period }
      end

      def tier(name, limit: nil, period: nil, unlimited: false)
        @tiers[name] = { limit: limit, period: period, unlimited: unlimited }
      end

      def check!(key, path, tier: nil)
        limits = resolve_limits(path, tier)
        return if limits[:unlimited]

        bucket_key = "#{key}:#{path}"

        @mutex.synchronize do
          record = @store[bucket_key]
          now = Time.now.to_f

          if record.nil? || (now - record[:window_start]) >= limits[:period]
            @store[bucket_key] = { count: 1, window_start: now }
            return
          end

          if record[:count] >= limits[:limit]
            retry_after = (limits[:period] - (now - record[:window_start])).ceil
            raise Errors::RateLimitExceeded.new(retry_after: retry_after)
          end

          record[:count] += 1
        end
      rescue NoMethodError, TypeError
        # Store failure
        if @on_store_failure == :fail_closed
          raise Errors::RateLimitExceeded.new("Rate limit store unavailable", retry_after: 60)
        end
        # fail_open: allow the request
      end

      def remaining(key, path, tier: nil)
        limits = resolve_limits(path, tier)
        return Float::INFINITY if limits[:unlimited]

        bucket_key = "#{key}:#{path}"

        @mutex.synchronize do
          record = @store[bucket_key]
          return limits[:limit] unless record

          now = Time.now.to_f
          if (now - record[:window_start]) >= limits[:period]
            return limits[:limit]
          end

          [limits[:limit] - record[:count], 0].max
        end
      end

      private

      def resolve_limits(path, tier)
        # Tier takes precedence, then per-path rule, then default
        if tier && @tiers[tier]
          tier_config = @tiers[tier]
          return { unlimited: true } if tier_config[:unlimited]
          return { limit: tier_config[:limit], period: tier_config[:period], unlimited: false }
        end

        if @rules[path]
          return { limit: @rules[path][:limit], period: @rules[path][:period], unlimited: false }
        end

        { limit: @default_limit, period: @default_period, unlimited: false }
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/auth/rate_limiter_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/auth/rate_limiter.rb spec/whoosh/auth/rate_limiter_spec.rb
git commit -m "feat: add RateLimiter with per-endpoint rules, tiers, and fail-open/closed"
```

---

### Task 4: Token Tracker

**Files:**
- Create: `lib/whoosh/auth/token_tracker.rb`
- Test: `spec/whoosh/auth/token_tracker_spec.rb`

Callback-based token usage tracking for billing integration.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/auth/token_tracker_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::TokenTracker do
  let(:tracker) { Whoosh::Auth::TokenTracker.new }

  describe "#record" do
    it "records token usage" do
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 120 })
      usage = tracker.usage_for("sk-1")
      expect(usage[:total_tokens]).to eq(170)
    end

    it "accumulates usage across calls" do
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 100 })
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 30, completion: 60 })
      usage = tracker.usage_for("sk-1")
      expect(usage[:total_tokens]).to eq(240)
    end
  end

  describe "#on_usage" do
    it "calls the callback on each record" do
      events = []
      tracker.on_usage do |key, endpoint, tokens|
        events << { key: key, endpoint: endpoint, tokens: tokens }
      end

      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 100 })
      expect(events.length).to eq(1)
      expect(events.first[:key]).to eq("sk-1")
      expect(events.first[:tokens][:prompt]).to eq(50)
    end
  end

  describe "#usage_for" do
    it "returns zero for unknown keys" do
      usage = tracker.usage_for("unknown")
      expect(usage[:total_tokens]).to eq(0)
    end

    it "includes per-endpoint breakdown" do
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 100 })
      tracker.record(key: "sk-1", endpoint: "/embed", tokens: { prompt: 200, completion: 0 })
      usage = tracker.usage_for("sk-1")
      expect(usage[:endpoints]["/chat"]).to eq(150)
      expect(usage[:endpoints]["/embed"]).to eq(200)
    end
  end

  describe "#reset" do
    it "clears usage for a key" do
      tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 100 })
      tracker.reset("sk-1")
      expect(tracker.usage_for("sk-1")[:total_tokens]).to eq(0)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/auth/token_tracker_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/auth/token_tracker.rb
# frozen_string_literal: true

module Whoosh
  module Auth
    class TokenTracker
      def initialize
        @usage = {}
        @callbacks = []
        @mutex = Mutex.new
      end

      def on_usage(&block)
        @callbacks << block
      end

      def record(key:, endpoint:, tokens:)
        total = tokens.values.sum

        @mutex.synchronize do
          @usage[key] ||= { total_tokens: 0, endpoints: {} }
          @usage[key][:total_tokens] += total
          @usage[key][:endpoints][endpoint] ||= 0
          @usage[key][:endpoints][endpoint] += total
        end

        @callbacks.each { |cb| cb.call(key, endpoint, tokens) }
      end

      def usage_for(key)
        @mutex.synchronize do
          data = @usage[key]
          return { total_tokens: 0, endpoints: {} } unless data

          { total_tokens: data[:total_tokens], endpoints: data[:endpoints].dup }
        end
      end

      def reset(key)
        @mutex.synchronize do
          @usage.delete(key)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/auth/token_tracker_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/auth/token_tracker.rb spec/whoosh/auth/token_tracker_spec.rb
git commit -m "feat: add TokenTracker with callback-based usage recording and per-key stats"
```

---

### Task 5: Access Control

**Files:**
- Create: `lib/whoosh/auth/access_control.rb`
- Test: `spec/whoosh/auth/access_control_spec.rb`

Per-key model access control with role-based whitelists.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/auth/access_control_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::AccessControl do
  let(:acl) { Whoosh::Auth::AccessControl.new }

  before do
    acl.role(:basic, models: ["claude-haiku"])
    acl.role(:standard, models: ["claude-haiku", "claude-sonnet"])
    acl.role(:premium, models: ["claude-haiku", "claude-sonnet", "claude-opus"])
  end

  describe "#check!" do
    it "allows access to permitted models" do
      expect { acl.check!(:standard, "claude-sonnet") }.not_to raise_error
    end

    it "denies access to unpermitted models" do
      expect { acl.check!(:basic, "claude-opus") }.to raise_error(Whoosh::Errors::ForbiddenError)
    end

    it "allows all models for premium role" do
      expect { acl.check!(:premium, "claude-opus") }.not_to raise_error
    end
  end

  describe "#models_for" do
    it "returns allowed models for a role" do
      expect(acl.models_for(:standard)).to eq(["claude-haiku", "claude-sonnet"])
    end

    it "returns empty array for unknown role" do
      expect(acl.models_for(:unknown)).to eq([])
    end
  end

  describe "#role" do
    it "registers roles with model lists" do
      acl.role(:custom, models: ["model-a"])
      expect(acl.models_for(:custom)).to eq(["model-a"])
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/auth/access_control_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/auth/access_control.rb
# frozen_string_literal: true

module Whoosh
  module Auth
    class AccessControl
      def initialize
        @roles = {}
      end

      def role(name, models: [])
        @roles[name] = models.dup.freeze
      end

      def check!(role, model)
        allowed = @roles[role]

        unless allowed && allowed.include?(model)
          raise Errors::ForbiddenError, "Model '#{model}' not allowed for role '#{role}'"
        end
      end

      def models_for(role)
        @roles[role] || []
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/auth/access_control_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/auth/access_control.rb spec/whoosh/auth/access_control_spec.rb
git commit -m "feat: add AccessControl with role-based model whitelisting"
```

---

## Chunk 3: App Integration

### Task 6: App Auth DSL

**Files:**
- Modify: `lib/whoosh/app.rb`
- Test: `spec/whoosh/app_auth_spec.rb`

Add `auth`, `rate_limit`, `token_tracking`, and `access_control` DSL blocks to App. Add auth middleware that can be applied to route groups.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/app_auth_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App auth integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "API key auth on routes" do
    before do
      application.auth do
        api_key header: "X-API-Key", keys: { "sk-valid" => { role: :standard } }
      end

      application.get "/public" do
        { open: true }
      end

      application.get "/protected", auth: :api_key do |req|
        { user: req.env["whoosh.auth"][:key] }
      end
    end

    it "allows unauthenticated access to public routes" do
      get "/public"
      expect(last_response.status).to eq(200)
    end

    it "allows authenticated access to protected routes" do
      get "/protected", {}, { "HTTP_X_API_KEY" => "sk-valid" }
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["user"]).to eq("sk-valid")
    end

    it "returns 401 for unauthenticated access to protected routes" do
      get "/protected"
      expect(last_response.status).to eq(401)
    end

    it "returns 401 for invalid key on protected routes" do
      get "/protected", {}, { "HTTP_X_API_KEY" => "sk-bad" }
      expect(last_response.status).to eq(401)
    end
  end

  describe "rate limiting DSL" do
    before do
      application.rate_limit do
        default limit: 3, period: 60
        rule "/limited", limit: 2, period: 60
      end

      application.get "/limited" do
        { ok: true }
      end
    end

    it "allows requests under the limit" do
      2.times { get "/limited" }
      expect(last_response.status).to eq(200)
    end

    it "returns 429 when over limit" do
      3.times { get "/limited" }
      expect(last_response.status).to eq(429)
    end
  end

  describe "access control DSL" do
    it "registers roles" do
      application.access_control do
        role :basic, models: ["claude-haiku"]
        role :premium, models: ["claude-haiku", "claude-opus"]
      end

      expect(application.acl.models_for(:basic)).to eq(["claude-haiku"])
      expect(application.acl.models_for(:premium)).to include("claude-opus")
    end
  end

  describe "token tracking DSL" do
    it "registers callbacks" do
      events = []
      application.token_tracking do
        on_usage do |key, endpoint, tokens|
          events << { key: key, endpoint: endpoint, tokens: tokens }
        end
      end

      application.token_tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 100 })
      expect(events.length).to eq(1)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/app_auth_spec.rb`
Expected: FAIL

- [ ] **Step 3: Update App with auth DSL**

Read `lib/whoosh/app.rb` first, then add the following:

**Add to attr_reader (line 7):**
Add `:authenticator, :rate_limiter_instance, :token_tracker, :acl` to attr_reader.

**Add to initialize (after plugin_registry):**
```ruby
      @authenticator = nil
      @rate_limiter_instance = nil
      @token_tracker = Auth::TokenTracker.new
      @acl = Auth::AccessControl.new
```

**Add these public methods (after setup_plugin_accessors):**

```ruby
    # --- Auth DSL ---

    def auth(&block)
      builder = AuthBuilder.new
      builder.instance_eval(&block)
      @authenticator = builder.build
    end

    def rate_limit(&block)
      builder = RateLimitBuilder.new
      builder.instance_eval(&block)
      @rate_limiter_instance = builder.build
    end

    def token_tracking(&block)
      builder = TokenTrackingBuilder.new(@token_tracker)
      builder.instance_eval(&block)
    end

    def access_control(&block)
      @acl.instance_eval(&block)
    end
```

**Update handle_request to support auth metadata:**
After schema validation, before calling handler, add auth check:
```ruby
      # Authenticate if route requires it
      if handler_metadata_requires_auth?(match[:metadata])
        auth_result = authenticate_request(request, match[:metadata])
        request.env["whoosh.auth"] = auth_result
      end

      # Rate limit check
      if @rate_limiter_instance
        key = request.env.dig("whoosh.auth", :key) || request.env["REMOTE_ADDR"] || "anonymous"
        @rate_limiter_instance.check!(key, request.path)
      end
```

**Add private helper methods:**
```ruby
    def handler_metadata_requires_auth?(metadata)
      metadata && metadata[:auth]
    end

    def authenticate_request(request, metadata)
      raise Errors::UnauthorizedError, "No authenticator configured" unless @authenticator
      @authenticator.authenticate(request)
    end
```

**Add inner builder classes at the bottom of app.rb (before the final `end`):**

```ruby
    # --- DSL Builders ---

    class AuthBuilder
      def initialize
        @strategies = {}
      end

      def api_key(header: "X-API-Key", keys: {})
        @strategies[:api_key] = Auth::ApiKey.new(keys: keys, header: header)
      end

      def jwt(secret:, algorithm: :hs256, expiry: 3600)
        @strategies[:jwt] = Auth::Jwt.new(secret: secret, algorithm: algorithm, expiry: expiry)
      end

      def build
        # Return the first strategy for now (multi-strategy can be added later)
        @strategies.values.first
      end
    end

    class RateLimitBuilder
      def initialize
        @default_limit = 60
        @default_period = 60
        @rules = []
        @tiers = []
        @on_store_failure = :fail_open
      end

      def default(limit:, period:)
        @default_limit = limit
        @default_period = period
      end

      def rule(path, limit:, period:)
        @rules << { path: path, limit: limit, period: period }
      end

      def tier(name, limit: nil, period: nil, unlimited: false)
        @tiers << { name: name, limit: limit, period: period, unlimited: unlimited }
      end

      def on_store_failure(strategy)
        @on_store_failure = strategy
      end

      def build
        limiter = Auth::RateLimiter.new(
          default_limit: @default_limit,
          default_period: @default_period,
          on_store_failure: @on_store_failure
        )
        @rules.each { |r| limiter.rule(r[:path], limit: r[:limit], period: r[:period]) }
        @tiers.each { |t| limiter.tier(t[:name], limit: t[:limit], period: t[:period], unlimited: t[:unlimited]) }
        limiter
      end
    end

    class TokenTrackingBuilder
      def initialize(tracker)
        @tracker = tracker
      end

      def on_usage(&block)
        @tracker.on_usage(&block)
      end
    end
```

**IMPORTANT:** The `auth: :api_key` metadata is passed through the router via `add_route`'s `**metadata` and stored in `match[:metadata]`. The existing `add_route` already passes `**metadata` to `@router.add`. So `auth: :api_key` flows naturally.

- [ ] **Step 4: Run all tests**

Run: `bundle exec rspec spec/whoosh/app_auth_spec.rb`
Expected: All pass

- [ ] **Step 5: Run full suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/whoosh/app.rb spec/whoosh/app_auth_spec.rb
git commit -m "feat: add auth DSL with API key, rate limiting, token tracking, and access control"
```

---

### Task 7: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 2: Smoke test**

```bash
bundle exec ruby -e "
require 'whoosh'
require 'rack/test'
include Rack::Test::Methods

app_instance = Whoosh::App.new

app_instance.auth do
  api_key header: 'X-API-Key', keys: { 'sk-test' => { role: :standard } }
end

app_instance.rate_limit do
  default limit: 100, period: 60
end

app_instance.access_control do
  role :standard, models: ['claude-haiku', 'claude-sonnet']
end

app_instance.get '/public' do
  { message: 'open' }
end

app_instance.get '/secure', auth: :api_key do |req|
  { key: req.env['whoosh.auth'][:key], role: req.env['whoosh.auth'][:role] }
end

define_method(:app) { app_instance.to_rack }

get '/public'
puts \"Public: #{last_response.status} #{last_response.body}\"

get '/secure', {}, { 'HTTP_X_API_KEY' => 'sk-test' }
puts \"Secure: #{last_response.status} #{last_response.body}\"

get '/secure'
puts \"No key: #{last_response.status}\"

puts 'Phase 3 Auth working!'
" 2>/dev/null
```

Expected:
```
Public: 200 {"message":"open"}
Secure: 200 {"key":"sk-test","role":"standard"}
No key: 401
Phase 3 Auth working!
```

---

## Phase 3 Completion Checklist

- [ ] `bundle exec rspec` — all green
- [ ] API key auth with header extraction and key registry
- [ ] JWT auth with HS256 signing, expiry, and secure comparison
- [ ] Rate limiter with default limits, per-endpoint rules, tier support
- [ ] Fail-open/fail-closed rate limit strategy
- [ ] Token usage tracking with callbacks
- [ ] Access control with role-based model whitelisting
- [ ] App DSL: `auth`, `rate_limit`, `token_tracking`, `access_control`
- [ ] Auth metadata on routes (`auth: :api_key`)
- [ ] Rate limit applied per-request
- [ ] All Phase 1-2 tests still pass

## Next Phase

After Phase 3 passes, proceed to **Phase 4: Streaming** — adding SSE, WebSocket, and LLM token streaming.
