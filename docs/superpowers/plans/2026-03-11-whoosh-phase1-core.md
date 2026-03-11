# Whoosh Phase 1: Core Framework Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a minimal working Whoosh framework that can define routes, validate schemas, serialize JSON, handle middleware, inject dependencies, and serve requests via Rack.

**Architecture:** Trie-based router + dry-schema/dry-types validation + Rack 3.0 middleware stack. All modules lazy-loaded via `autoload`. App class combines everything behind a `to_rack` method for any Rack server.

**Tech Stack:** Ruby 3.4+, Rack 3.0, dry-schema, dry-types, RSpec, rack-test

**Spec:** `docs/superpowers/specs/2026-03-11-whoosh-design.md`

---

## Chunk 1: Gem Skeleton, Types, Errors, Config

### Task 1: Gem Skeleton

**Files:**
- Create: `whoosh.gemspec`
- Create: `Gemfile`
- Create: `Rakefile`
- Create: `lib/whoosh.rb`
- Create: `lib/whoosh/version.rb`
- Create: `exe/whoosh`
- Create: `.rspec`
- Create: `spec/spec_helper.rb`

- [ ] **Step 1: Create gemspec**

```ruby
# whoosh.gemspec
# frozen_string_literal: true

require_relative "lib/whoosh/version"

Gem::Specification.new do |spec|
  spec.name = "whoosh"
  spec.version = Whoosh::VERSION
  spec.authors = ["Johannes Dwi Cahyo"]
  spec.summary = "AI-first Ruby API framework"
  spec.description = "A fast, secure Ruby API framework inspired by FastAPI with built-in MCP support, auto-generated OpenAPI docs, and seamless AI gem ecosystem integration."
  spec.homepage = "https://github.com/johannesdwicahyo/whoosh"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["whoosh"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rack", "~> 3.0"
  spec.add_dependency "dry-schema", "~> 1.13"
  spec.add_dependency "dry-types", "~> 1.7"
  spec.add_dependency "thor", "~> 1.3"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rack-test", "~> 2.1"
  spec.add_development_dependency "rake", "~> 13.0"
end
```

- [ ] **Step 2: Create version file**

```ruby
# lib/whoosh/version.rb
# frozen_string_literal: true

module Whoosh
  VERSION = "0.1.0"
end
```

- [ ] **Step 3: Create main module with autoloads**

```ruby
# lib/whoosh.rb
# frozen_string_literal: true

require_relative "whoosh/version"

module Whoosh
  autoload :App,                 "whoosh/app"
  autoload :Config,              "whoosh/config"
  autoload :DependencyInjection, "whoosh/dependency_injection"
  autoload :Endpoint,            "whoosh/endpoint"
  autoload :Errors,              "whoosh/errors"
  autoload :Logger,              "whoosh/logger"
  autoload :Request,             "whoosh/request"
  autoload :Response,            "whoosh/response"
  autoload :Router,              "whoosh/router"
  autoload :Schema,              "whoosh/schema"
  autoload :Types,               "whoosh/types"

  module Auth
    autoload :ApiKey,         "whoosh/auth/api_key"
    autoload :Jwt,            "whoosh/auth/jwt"
    autoload :OAuth2,         "whoosh/auth/oauth2"
    autoload :RateLimiter,    "whoosh/auth/rate_limiter"
    autoload :TokenTracker,   "whoosh/auth/token_tracker"
    autoload :AccessControl,  "whoosh/auth/access_control"
  end

  module MCP
    autoload :Server,        "whoosh/mcp/server"
    autoload :Client,        "whoosh/mcp/client"
    autoload :ClientManager, "whoosh/mcp/client_manager"
    autoload :Protocol,      "whoosh/mcp/protocol"
  end

  module Middleware
    autoload :Stack,           "whoosh/middleware/stack"
    autoload :Cors,            "whoosh/middleware/cors"
    autoload :RequestLogger,   "whoosh/middleware/request_logger"
    autoload :SecurityHeaders, "whoosh/middleware/security_headers"
    autoload :RequestLimit,    "whoosh/middleware/request_limit"
  end

  module Streaming
    autoload :SSE,       "whoosh/streaming/sse"
    autoload :WebSocket, "whoosh/streaming/websocket"
    autoload :LlmStream, "whoosh/streaming/llm_stream"
  end

  module OpenAPI
    autoload :Generator,       "whoosh/openapi/generator"
    autoload :UI,              "whoosh/openapi/ui"
    autoload :SchemaConverter, "whoosh/openapi/schema_converter"
  end

  module Serialization
    autoload :Json,       "whoosh/serialization/json"
    autoload :Negotiator, "whoosh/serialization/negotiator"
  end

  module Plugins
    autoload :Registry, "whoosh/plugins/registry"
    autoload :Base,     "whoosh/plugins/base"
  end
end
```

- [ ] **Step 4: Create supporting files**

```ruby
# Gemfile
# frozen_string_literal: true

source "https://rubygems.org"
gemspec
```

```ruby
# Rakefile
# frozen_string_literal: true

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)
task default: :spec
```

```
# .rspec
--format documentation
--color
--require spec_helper
```

```ruby
# spec/spec_helper.rb
# frozen_string_literal: true

require "whoosh"
require "rack/test"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
end
```

- [ ] **Step 5: Create CLI executable stub**

```ruby
#!/usr/bin/env ruby
# exe/whoosh
# frozen_string_literal: true

require "whoosh"
# CLI implementation will be added in Phase 8
puts "Whoosh v#{Whoosh::VERSION}"
```

Make executable: `chmod +x exe/whoosh`

- [ ] **Step 6: Install dependencies and verify**

Run: `bundle install`
Expected: All gems install successfully

- [ ] **Step 7: Verify gem loads**

Run: `bundle exec ruby -e "require 'whoosh'; puts Whoosh::VERSION"`
Expected: `0.1.0`

- [ ] **Step 8: Commit**

```bash
git add whoosh.gemspec Gemfile Gemfile.lock Rakefile .rspec lib/whoosh.rb lib/whoosh/version.rb exe/whoosh spec/spec_helper.rb
git commit -m "feat: initialize whoosh gem skeleton with autoloads and dev dependencies"
```

---

### Task 2: Types

**Files:**
- Create: `lib/whoosh/types.rb`
- Test: `spec/whoosh/types_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/types_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Types do
  describe "Bool" do
    it "coerces true string" do
      expect(Whoosh::Types::Bool["true"]).to be true
    end

    it "coerces false string" do
      expect(Whoosh::Types::Bool["false"]).to be false
    end

    it "accepts true" do
      expect(Whoosh::Types::Bool[true]).to be true
    end

    it "accepts false" do
      expect(Whoosh::Types::Bool[false]).to be false
    end

    it "rejects invalid values" do
      expect { Whoosh::Types::Bool["invalid"] }.to raise_error(Dry::Types::CoercionError)
    end
  end

  describe "String" do
    it "is available" do
      expect(Whoosh::Types::String["hello"]).to eq("hello")
    end
  end

  describe "Integer" do
    it "coerces string to integer" do
      expect(Whoosh::Types::Coercible::Integer["42"]).to eq(42)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/types_spec.rb`
Expected: FAIL — `cannot load such file -- whoosh/types`

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/types.rb
# frozen_string_literal: true

require "dry-types"

module Whoosh
  module Types
    include Dry.Types()

    Bool = Types::Params::Bool
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/types_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/types.rb spec/whoosh/types_spec.rb
git commit -m "feat: add Whoosh::Types with Bool alias wrapping dry-types"
```

---

### Task 3: Errors

**Files:**
- Create: `lib/whoosh/errors.rb`
- Test: `spec/whoosh/errors_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/errors_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Errors do
  describe Whoosh::Errors::WhooshError do
    it "is a StandardError" do
      expect(Whoosh::Errors::WhooshError.new("test")).to be_a(StandardError)
    end
  end

  describe Whoosh::Errors::ValidationError do
    it "has status 422" do
      error = Whoosh::Errors::ValidationError.new([{ field: "name", message: "is required" }])
      expect(error.status).to eq(422)
    end

    it "has error type" do
      error = Whoosh::Errors::ValidationError.new([])
      expect(error.error_type).to eq("validation_failed")
    end

    it "stores details" do
      details = [{ field: "age", message: "must be positive", value: -1 }]
      error = Whoosh::Errors::ValidationError.new(details)
      expect(error.details).to eq(details)
    end

    it "serializes to JSON hash" do
      details = [{ field: "age", message: "must be positive" }]
      error = Whoosh::Errors::ValidationError.new(details)
      expect(error.to_h).to eq({ error: "validation_failed", details: details })
    end
  end

  describe Whoosh::Errors::NotFoundError do
    it "has status 404" do
      expect(Whoosh::Errors::NotFoundError.new.status).to eq(404)
    end
  end

  describe Whoosh::Errors::UnauthorizedError do
    it "has status 401" do
      expect(Whoosh::Errors::UnauthorizedError.new.status).to eq(401)
    end
  end

  describe Whoosh::Errors::ForbiddenError do
    it "has status 403" do
      expect(Whoosh::Errors::ForbiddenError.new.status).to eq(403)
    end
  end

  describe Whoosh::Errors::RateLimitExceeded do
    it "has status 429" do
      error = Whoosh::Errors::RateLimitExceeded.new(retry_after: 60)
      expect(error.status).to eq(429)
    end

    it "stores retry_after" do
      error = Whoosh::Errors::RateLimitExceeded.new(retry_after: 60)
      expect(error.retry_after).to eq(60)
    end
  end

  describe Whoosh::Errors::DependencyError do
    it "is a WhooshError" do
      expect(Whoosh::Errors::DependencyError.new("circular")).to be_a(Whoosh::Errors::WhooshError)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/errors_spec.rb`
Expected: FAIL — `cannot load such file -- whoosh/errors`

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/errors.rb
# frozen_string_literal: true

module Whoosh
  module Errors
    class WhooshError < StandardError; end

    class HttpError < WhooshError
      attr_reader :status, :error_type

      def initialize(message = nil, status: 500, error_type: "internal_error")
        @status = status
        @error_type = error_type
        super(message || error_type)
      end

      def to_h
        { error: error_type }
      end
    end

    class ValidationError < HttpError
      attr_reader :details

      def initialize(details = [])
        @details = details
        super("Validation failed", status: 422, error_type: "validation_failed")
      end

      def to_h
        { error: error_type, details: details }
      end
    end

    class NotFoundError < HttpError
      def initialize(message = "Not found")
        super(message, status: 404, error_type: "not_found")
      end
    end

    class UnauthorizedError < HttpError
      def initialize(message = "Unauthorized")
        super(message, status: 401, error_type: "unauthorized")
      end
    end

    class ForbiddenError < HttpError
      def initialize(message = "Forbidden")
        super(message, status: 403, error_type: "forbidden")
      end
    end

    class RateLimitExceeded < HttpError
      attr_reader :retry_after

      def initialize(message = "Rate limit exceeded", retry_after: 60)
        @retry_after = retry_after
        super(message, status: 429, error_type: "rate_limited")
      end

      def to_h
        super.merge(retry_after: retry_after)
      end
    end

    class DependencyError < WhooshError; end

    class GuardrailsViolation < WhooshError; end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/errors_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/errors.rb spec/whoosh/errors_spec.rb
git commit -m "feat: add error classes with HTTP status codes and JSON serialization"
```

---

### Task 4: Config

**Files:**
- Create: `lib/whoosh/config.rb`
- Test: `spec/whoosh/config_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/config_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Whoosh::Config do
  describe ".load" do
    it "returns defaults when no config file exists" do
      config = Whoosh::Config.load(root: "/nonexistent")
      expect(config.port).to eq(9292)
      expect(config.host).to eq("localhost")
      expect(config.env).to eq("development")
    end

    it "loads from YAML file" do
      Dir.mktmpdir do |dir|
        config_dir = File.join(dir, "config")
        Dir.mkdir(config_dir)
        File.write(File.join(config_dir, "app.yml"), <<~YAML)
          app:
            name: "Test API"
            port: 3000
        YAML

        config = Whoosh::Config.load(root: dir)
        expect(config.port).to eq(3000)
        expect(config.app_name).to eq("Test API")
      end
    end

    it "environment variables take precedence" do
      Dir.mktmpdir do |dir|
        config_dir = File.join(dir, "config")
        Dir.mkdir(config_dir)
        File.write(File.join(config_dir, "app.yml"), <<~YAML)
          app:
            port: 3000
        YAML

        ENV["WHOOSH_PORT"] = "4000"
        config = Whoosh::Config.load(root: dir)
        expect(config.port).to eq(4000)
      ensure
        ENV.delete("WHOOSH_PORT")
      end
    end
  end

  describe "DSL overrides" do
    it "allows setting values" do
      config = Whoosh::Config.load(root: "/nonexistent")
      config.port = 5000
      expect(config.port).to eq(5000)
    end
  end

  describe "json_engine" do
    it "defaults to :json" do
      config = Whoosh::Config.load(root: "/nonexistent")
      expect(config.json_engine).to eq(:json)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/config_spec.rb`
Expected: FAIL — `cannot load such file -- whoosh/config`

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/config.rb
# frozen_string_literal: true

require "yaml"
require "erb"

module Whoosh
  class Config
    DEFAULTS = {
      "app" => {
        "name" => "Whoosh App",
        "env" => "development",
        "port" => 9292,
        "host" => "localhost"
      },
      "server" => {
        "type" => "falcon",
        "workers" => "auto",
        "timeout" => 30
      },
      "logging" => {
        "level" => "info",
        "format" => "json"
      },
      "docs" => {
        "enabled" => true
      },
      "performance" => {
        "yjit" => true,
        "yjit_exec_mem" => 64
      }
    }.freeze

    ENV_MAP = {
      "WHOOSH_PORT" => ["app", "port"],
      "WHOOSH_HOST" => ["app", "host"],
      "WHOOSH_ENV" => ["app", "env"],
      "WHOOSH_LOG_LEVEL" => ["logging", "level"],
      "WHOOSH_LOG_FORMAT" => ["logging", "format"]
    }.freeze

    attr_accessor :json_engine
    attr_reader :data

    def self.load(root:)
      new(root: root)
    end

    def initialize(root:)
      @data = deep_dup(DEFAULTS)
      @root = root
      @json_engine = :json

      load_yaml
      apply_env
    end

    def port
      @data.dig("app", "port")
    end

    def port=(value)
      @data["app"]["port"] = value.to_i
    end

    def host
      @data.dig("app", "host")
    end

    def host=(value)
      @data["app"]["host"] = value
    end

    def env
      @data.dig("app", "env")
    end

    def app_name
      @data.dig("app", "name")
    end

    def server_type
      @data.dig("server", "type")
    end

    def log_level
      @data.dig("logging", "level")
    end

    def log_format
      @data.dig("logging", "format")
    end

    def docs_enabled?
      @data.dig("docs", "enabled")
    end

    def shutdown_timeout
      @data.dig("server", "timeout") || 30
    end

    def development?
      env == "development"
    end

    def production?
      env == "production"
    end

    def test?
      env == "test"
    end

    private

    def load_yaml
      path = File.join(@root, "config", "app.yml")
      return unless File.exist?(path)

      content = ERB.new(File.read(path)).result
      yaml = YAML.safe_load(content, permitted_classes: [Symbol]) || {}
      deep_merge!(@data, yaml)
    end

    def apply_env
      ENV_MAP.each do |env_key, path|
        value = ENV[env_key]
        next unless value

        target = @data
        path[0...-1].each { |key| target = target[key] ||= {} }
        target[path.last] = coerce_value(value, @data.dig(*path))
      end
    end

    def coerce_value(value, existing)
      case existing
      when Integer then value.to_i
      when Float then value.to_f
      when TrueClass, FalseClass then %w[true 1 yes].include?(value.downcase)
      else value
      end
    end

    def deep_dup(hash)
      hash.each_with_object({}) do |(k, v), result|
        result[k] = v.is_a?(Hash) ? deep_dup(v) : v
      end
    end

    def deep_merge!(target, source)
      source.each do |key, value|
        if value.is_a?(Hash) && target[key].is_a?(Hash)
          deep_merge!(target[key], value)
        else
          target[key] = value
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/config_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/config.rb spec/whoosh/config_spec.rb
git commit -m "feat: add Config with YAML loading, ENV overrides, and defaults"
```

---

## Chunk 2: Request, Response, Router

### Task 5: Request

**Files:**
- Create: `lib/whoosh/request.rb`
- Test: `spec/whoosh/request_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/request_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack"

RSpec.describe Whoosh::Request do
  def build_env(method: "GET", path: "/test", body: nil, headers: {}, content_type: nil)
    opts = { method: method }
    opts[:input] = body if body
    opts["CONTENT_TYPE"] = content_type if content_type
    env = Rack::MockRequest.env_for(path, **opts)
    headers.each do |key, value|
      env["HTTP_#{key.upcase.tr('-', '_')}"] = value
    end
    env
  end

  describe "#method" do
    it "returns the HTTP method" do
      req = Whoosh::Request.new(build_env(method: "POST"))
      expect(req.method).to eq("POST")
    end
  end

  describe "#path" do
    it "returns the request path" do
      req = Whoosh::Request.new(build_env(path: "/api/users"))
      expect(req.path).to eq("/api/users")
    end
  end

  describe "#params" do
    it "returns path params" do
      req = Whoosh::Request.new(build_env)
      req.path_params = { id: "42" }
      expect(req.params[:id]).to eq("42")
    end
  end

  describe "#body" do
    it "parses JSON body" do
      json = '{"name":"test","age":25}'
      req = Whoosh::Request.new(build_env(
        method: "POST",
        body: json,
        content_type: "application/json"
      ))
      expect(req.body).to eq({ "name" => "test", "age" => 25 })
    end

    it "returns nil for empty body" do
      req = Whoosh::Request.new(build_env)
      expect(req.body).to be_nil
    end
  end

  describe "#headers" do
    it "returns request headers" do
      req = Whoosh::Request.new(build_env(headers: { "X-Api-Key" => "secret" }))
      expect(req.headers["X-Api-Key"]).to eq("secret")
    end
  end

  describe "#id" do
    it "returns X-Request-ID if present" do
      req = Whoosh::Request.new(build_env(headers: { "X-Request-Id" => "abc-123" }))
      expect(req.id).to eq("abc-123")
    end

    it "generates a request ID if not present" do
      req = Whoosh::Request.new(build_env)
      expect(req.id).to match(/\A[a-f0-9-]+\z/)
    end
  end

  describe "#query_params" do
    it "parses query string" do
      req = Whoosh::Request.new(build_env(path: "/test?page=2&limit=10"))
      expect(req.query_params["page"]).to eq("2")
      expect(req.query_params["limit"]).to eq("10")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/request_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/request.rb
# frozen_string_literal: true

require "json"
require "securerandom"
require "rack"

module Whoosh
  class Request
    attr_accessor :path_params
    attr_reader :env

    def initialize(env)
      @env = env
      @rack_request = Rack::Request.new(env)
      @path_params = {}
    end

    def method
      @rack_request.request_method
    end

    def path
      @rack_request.path_info
    end

    def params
      @params ||= query_params.merge(@path_params)
    end

    def query_params
      @query_params ||= Rack::Utils.parse_query(@rack_request.query_string)
    end

    def body
      @body ||= parse_body
    end

    def headers
      @headers ||= extract_headers
    end

    def id
      @id ||= headers["X-Request-Id"] || SecureRandom.uuid
    end

    def content_type
      @rack_request.content_type
    end

    private

    def parse_body
      raw = @rack_request.body&.read
      return nil if raw.nil? || raw.empty?

      @rack_request.body.rewind

      case content_type
      when /json/
        JSON.parse(raw)
      else
        raw
      end
    end

    def extract_headers
      @env.each_with_object({}) do |(key, value), headers|
        next unless key.start_with?("HTTP_")

        header_name = key.sub("HTTP_", "").split("_").map(&:capitalize).join("-")
        headers[header_name] = value
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/request_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/request.rb spec/whoosh/request_spec.rb
git commit -m "feat: add Request wrapping Rack env with body parsing and headers"
```

---

### Task 6: Response

**Files:**
- Create: `lib/whoosh/response.rb`
- Test: `spec/whoosh/response_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/response_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Response do
  describe ".json" do
    it "creates a JSON response" do
      status, headers, body = Whoosh::Response.json({ name: "test" })
      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("application/json")
      parsed = JSON.parse(body.first)
      expect(parsed["name"]).to eq("test")
    end

    it "accepts a custom status" do
      status, _, _ = Whoosh::Response.json({ created: true }, status: 201)
      expect(status).to eq(201)
    end
  end

  describe ".error" do
    it "creates an error response from HttpError" do
      error = Whoosh::Errors::ValidationError.new([{ field: "name", message: "required" }])
      status, headers, body = Whoosh::Response.error(error)
      expect(status).to eq(422)
      expect(headers["content-type"]).to eq("application/json")
      parsed = JSON.parse(body.first)
      expect(parsed["error"]).to eq("validation_failed")
    end

    it "includes Retry-After for rate limit errors" do
      error = Whoosh::Errors::RateLimitExceeded.new(retry_after: 120)
      _, headers, _ = Whoosh::Response.error(error)
      expect(headers["retry-after"]).to eq("120")
    end
  end

  describe ".not_found" do
    it "returns 404" do
      status, _, body = Whoosh::Response.not_found
      expect(status).to eq(404)
      parsed = JSON.parse(body.first)
      expect(parsed["error"]).to eq("not_found")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/response_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/response.rb
# frozen_string_literal: true

module Whoosh
  class Response
    def self.json(data, status: 200, headers: {})
      body = Serialization::Json.encode(data)
      response_headers = {
        "content-type" => "application/json",
        "content-length" => body.bytesize.to_s
      }.merge(headers)

      [status, response_headers, [body]]
    end

    def self.error(error, production: false)
      headers = { "content-type" => "application/json" }

      if error.is_a?(Errors::RateLimitExceeded)
        headers["retry-after"] = error.retry_after.to_s
      end

      body = if error.is_a?(Errors::HttpError)
        error.to_h
      else
        hash = { error: "internal_error" }
        hash[:message] = error.message unless production
        hash
      end

      [error.is_a?(Errors::HttpError) ? error.status : 500, headers, [Serialization::Json.encode(body)]]
    end

    def self.not_found
      error(Errors::NotFoundError.new)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/response_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/response.rb spec/whoosh/response_spec.rb
git commit -m "feat: add Response with JSON serialization and error formatting"
```

---

### Task 7: Router

**Files:**
- Create: `lib/whoosh/router.rb`
- Test: `spec/whoosh/router_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/router_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Router do
  let(:router) { Whoosh::Router.new }

  describe "#add and #match" do
    it "matches a simple route" do
      handler = -> { "hello" }
      router.add("GET", "/health", handler)

      match = router.match("GET", "/health")
      expect(match).not_to be_nil
      expect(match[:handler]).to eq(handler)
      expect(match[:params]).to be_empty
    end

    it "matches route with path params" do
      handler = -> { "user" }
      router.add("GET", "/users/:id", handler)

      match = router.match("GET", "/users/42")
      expect(match[:handler]).to eq(handler)
      expect(match[:params]).to eq({ id: "42" })
    end

    it "matches route with multiple path params" do
      handler = -> { "comment" }
      router.add("GET", "/users/:user_id/posts/:post_id", handler)

      match = router.match("GET", "/users/1/posts/99")
      expect(match[:params]).to eq({ user_id: "1", post_id: "99" })
    end

    it "returns nil for no match" do
      router.add("GET", "/health", -> { "ok" })
      expect(router.match("GET", "/missing")).to be_nil
    end

    it "differentiates HTTP methods" do
      get_handler = -> { "get" }
      post_handler = -> { "post" }
      router.add("GET", "/items", get_handler)
      router.add("POST", "/items", post_handler)

      expect(router.match("GET", "/items")[:handler]).to eq(get_handler)
      expect(router.match("POST", "/items")[:handler]).to eq(post_handler)
    end

    it "stores route metadata" do
      handler = -> { "ok" }
      router.add("POST", "/chat", handler, request_schema: "ChatRequest", mcp: true)

      match = router.match("POST", "/chat")
      expect(match[:metadata][:request_schema]).to eq("ChatRequest")
      expect(match[:metadata][:mcp]).to be true
    end
  end

  describe "#routes" do
    it "returns all registered routes" do
      router.add("GET", "/a", -> {})
      router.add("POST", "/b", -> {})

      routes = router.routes
      expect(routes.length).to eq(2)
      expect(routes.map { |r| r[:method] }).to contain_exactly("GET", "POST")
      expect(routes.map { |r| r[:path] }).to contain_exactly("/a", "/b")
    end
  end

  describe "#freeze!" do
    it "prevents adding new routes after freeze" do
      router.add("GET", "/a", -> {})
      router.freeze!

      expect { router.add("GET", "/b", -> {}) }.to raise_error(RuntimeError, /frozen/)
    end

    it "still matches after freeze" do
      handler = -> { "ok" }
      router.add("GET", "/a", handler)
      router.freeze!

      expect(router.match("GET", "/a")[:handler]).to eq(handler)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/router_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/router.rb
# frozen_string_literal: true

module Whoosh
  class Router
    class TrieNode
      attr_accessor :handlers, :children, :param_name, :is_param

      def initialize
        @children = {}
        @handlers = {}
        @param_name = nil
        @is_param = false
      end
    end

    def initialize
      @root = TrieNode.new
      @routes = []
      @frozen = false
    end

    def add(method, path, handler, **metadata)
      raise "Router is frozen — cannot add routes after boot" if @frozen

      node = @root
      segments = split_path(path)

      segments.each do |segment|
        if segment.start_with?(":")
          child = node.children[:_param] ||= TrieNode.new
          child.is_param = true
          child.param_name = segment[1..].to_sym
          node = child
        else
          node = node.children[segment] ||= TrieNode.new
        end
      end

      node.handlers[method] = { handler: handler, metadata: metadata }
      @routes << { method: method, path: path, handler: handler, metadata: metadata }
    end

    def match(method, path)
      node = @root
      params = {}
      segments = split_path(path)

      segments.each do |segment|
        if node.children[segment]
          node = node.children[segment]
        elsif node.children[:_param]
          node = node.children[:_param]
          params[node.param_name] = segment
        else
          return nil
        end
      end

      entry = node.handlers[method]
      return nil unless entry

      { handler: entry[:handler], params: params, metadata: entry[:metadata] }
    end

    def routes
      @routes.map do |route|
        { method: route[:method], path: route[:path], metadata: route[:metadata] }
      end
    end

    def freeze!
      @frozen = true
    end

    private

    def split_path(path)
      path.split("/").reject(&:empty?)
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/router_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/router.rb spec/whoosh/router_spec.rb
git commit -m "feat: add trie-based Router with path params, metadata, and freeze"
```

---

## Chunk 3: Schema, Serialization

### Task 8: Schema

**Files:**
- Create: `lib/whoosh/schema.rb`
- Test: `spec/whoosh/schema_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/schema_spec.rb
# frozen_string_literal: true

require "spec_helper"

# Test schemas
class TestUserSchema < Whoosh::Schema
  field :name,  String,  required: true, desc: "User name"
  field :email, String,  required: true, desc: "User email"
  field :age,   Integer, min: 0, max: 150
  field :active, Whoosh::Types::Bool, default: true
  field :role,  String,  default: "user"
end

class TestAddressSchema < Whoosh::Schema
  field :street, String, required: true
  field :city,   String, required: true
end

class TestProfileSchema < Whoosh::Schema
  field :user,    TestUserSchema, required: true
  field :address, TestAddressSchema
end

RSpec.describe Whoosh::Schema do
  describe ".validate" do
    it "passes with valid data" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com", age: 30 })
      expect(result).to be_success
      expect(result.data[:name]).to eq("Alice")
    end

    it "applies defaults" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com" })
      expect(result.data[:role]).to eq("user")
    end

    it "fails with missing required fields" do
      result = TestUserSchema.validate({ age: 30 })
      expect(result).not_to be_success
      expect(result.errors).to include(
        hash_including(field: :name, message: a_string_matching(/required|missing|filled/i))
      )
    end

    it "fails with out-of-range values" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com", age: -5 })
      expect(result).not_to be_success
      expect(result.errors).to include(
        hash_including(field: :age)
      )
    end

    it "coerces string to integer" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com", age: "25" })
      expect(result).to be_success
      expect(result.data[:age]).to eq(25)
    end

    it "validates Bool field" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com", active: "true" })
      expect(result).to be_success
      expect(result.data[:active]).to be true
    end

    it "applies Bool default" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com" })
      expect(result).to be_success
      expect(result.data[:active]).to be true
    end
  end

  describe "nested schemas" do
    it "validates nested data" do
      result = TestProfileSchema.validate({
        user: { name: "Alice", email: "a@b.com" },
        address: { street: "123 Main", city: "NYC" }
      })
      expect(result).to be_success
      expect(result.data[:user][:name]).to eq("Alice")
    end

    it "fails on invalid nested data" do
      result = TestProfileSchema.validate({
        user: { email: "a@b.com" }
      })
      expect(result).not_to be_success
    end
  end

  describe ".fields" do
    it "returns field definitions" do
      fields = TestUserSchema.fields
      expect(fields[:name]).to include(type: String, required: true, desc: "User name")
      expect(fields[:role]).to include(default: "user")
    end
  end

  describe ".to_h (serialization)" do
    it "serializes data to hash" do
      result = TestUserSchema.validate({ name: "Alice", email: "a@b.com" })
      hash = TestUserSchema.serialize(result.data)
      expect(hash).to eq({ name: "Alice", email: "a@b.com", age: nil, role: "user" })
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/schema_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/schema.rb
# frozen_string_literal: true

require "dry-schema"
require "dry-types"

module Whoosh
  class Schema
    class Result
      attr_reader :data, :errors

      def initialize(data:, errors:)
        @data = data
        @errors = errors
      end

      def success?
        @errors.empty?
      end
    end

    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@fields, {})
        subclass.instance_variable_set(:@contract, nil)
      end

      def field(name, type, **options)
        @fields[name] = options.merge(type: type)
        @contract = nil # Reset cached contract
      end

      def fields
        @fields
      end

      def validate(data)
        input = coerce_input(data)

        # First pass: dry-schema validation
        result = contract.call(input)

        unless result.success?
          errors = result.errors.to_h.flat_map do |field_name, messages|
            messages.map do |msg|
              { field: field_name, message: msg, value: data[field_name] || data[field_name.to_s] }
            end
          end
          return Result.new(data: nil, errors: errors)
        end

        validated = result.to_h

        # Second pass: min/max constraints + nested schema validation
        errors = []
        @fields.each do |name, opts|
          value = validated[name]
          next if value.nil?

          # Nested schema validation
          if schema_type?(opts[:type])
            nested_result = opts[:type].validate(value)
            unless nested_result.success?
              nested_result.errors.each do |err|
                errors << { field: :"#{name}.#{err[:field]}", message: err[:message], value: err[:value] }
              end
            else
              validated[name] = nested_result.data
            end
          end

          # Min/max constraints
          if opts[:min] && value.is_a?(Numeric) && value < opts[:min]
            errors << { field: name, message: "must be greater than or equal to #{opts[:min]}", value: value }
          end
          if opts[:max] && value.is_a?(Numeric) && value > opts[:max]
            errors << { field: name, message: "must be less than or equal to #{opts[:max]}", value: value }
          end
        end

        return Result.new(data: nil, errors: errors) unless errors.empty?

        Result.new(data: apply_defaults(validated), errors: [])
      end

      def serialize(data)
        return data unless data.is_a?(Hash)

        @fields.each_with_object({}) do |(name, opts), hash|
          value = data[name]
          if value.nil?
            hash[name] = opts[:default]
          elsif schema_type?(opts[:type])
            hash[name] = opts[:type].serialize(value)
          else
            hash[name] = serialize_value(value)
          end
        end
      end

      private

      def contract
        @contract ||= build_contract
      end

      def build_contract
        field_defs = @fields

        Dry::Schema.Params do
          field_defs.each do |name, opts|
            type = opts[:type]

            if type.is_a?(Class) && type < Whoosh::Schema
              # Nested schema — accept as hash, validate separately
              if opts[:required]
                required(name).filled(:hash)
              else
                optional(name).maybe(:hash)
              end
            elsif type.is_a?(Dry::Types::Type) || (type.respond_to?(:ancestors) && type.ancestors.include?(Dry::Types::Type) rescue false)
              # Dry::Types object (e.g., Whoosh::Types::Bool)
              if opts[:required]
                required(name).filled(:bool)
              else
                optional(name).maybe(:bool)
              end
            else
              dry_type = map_type(type)
              if opts[:required]
                required(name).filled(dry_type)
              else
                optional(name).maybe(dry_type)
              end
            end
          end
        end
      end

      def map_type(type)
        case type.to_s
        when "String" then :string
        when "Integer" then :integer
        when "Float" then :float
        when "Hash" then :hash
        when "Array" then :array
        when "Time", "DateTime" then :time
        else :string
        end
      end

      def schema_type?(type)
        type.is_a?(Class) && type < Whoosh::Schema
      rescue TypeError
        false
      end

      def coerce_input(data)
        return {} if data.nil?

        data.transform_keys(&:to_sym)
      end

      def apply_defaults(data)
        @fields.each do |name, opts|
          if data[name].nil? && opts.key?(:default)
            data[name] = opts[:default]
          end
        end
        data
      end

      def serialize_value(value)
        case value
        when Time, DateTime
          value.iso8601
        when BigDecimal
          value.to_s("F")
        else
          value
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/schema_spec.rb`
Expected: All pass (some tests may need minor adjustments based on dry-schema error message wording)

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/schema.rb spec/whoosh/schema_spec.rb
git commit -m "feat: add Schema DSL wrapping dry-schema with validation, defaults, and nesting"
```

---

### Task 9: JSON Serialization

**Files:**
- Create: `lib/whoosh/serialization/json.rb`
- Create: `lib/whoosh/serialization/negotiator.rb`
- Test: `spec/whoosh/serialization/json_spec.rb`
- Test: `spec/whoosh/serialization/negotiator_spec.rb`

- [ ] **Step 1: Write the failing test for JSON engine**

```ruby
# spec/whoosh/serialization/json_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Serialization::Json do
  describe ".encode" do
    it "encodes hash to JSON string" do
      result = Whoosh::Serialization::Json.encode({ name: "test", count: 42 })
      parsed = JSON.parse(result)
      expect(parsed["name"]).to eq("test")
      expect(parsed["count"]).to eq(42)
    end

    it "handles Time as ISO 8601" do
      time = Time.utc(2026, 3, 11, 10, 30, 0)
      result = Whoosh::Serialization::Json.encode({ created_at: time })
      parsed = JSON.parse(result)
      expect(parsed["created_at"]).to eq("2026-03-11T10:30:00Z")
    end
  end

  describe ".decode" do
    it "decodes JSON string to hash" do
      result = Whoosh::Serialization::Json.decode('{"name":"test"}')
      expect(result).to eq({ "name" => "test" })
    end

    it "returns nil for nil input" do
      expect(Whoosh::Serialization::Json.decode(nil)).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/serialization/json_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write JSON engine**

```ruby
# lib/whoosh/serialization/json.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module Serialization
    class Json
      def self.encode(data)
        JSON.generate(prepare(data))
      end

      def self.decode(raw)
        return nil if raw.nil? || raw.empty?

        JSON.parse(raw)
      end

      def self.content_type
        "application/json"
      end

      def self.prepare(obj)
        case obj
        when Hash
          obj.transform_values { |v| prepare(v) }
        when Array
          obj.map { |v| prepare(v) }
        when Time, DateTime
          obj.iso8601
        when BigDecimal
          obj.to_s("F")
        else
          obj
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run JSON test to verify it passes**

Run: `bundle exec rspec spec/whoosh/serialization/json_spec.rb`
Expected: All pass

- [ ] **Step 5: Write the failing test for Negotiator**

```ruby
# spec/whoosh/serialization/negotiator_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Serialization::Negotiator do
  describe ".for_accept" do
    it "returns JSON serializer for application/json" do
      serializer = Whoosh::Serialization::Negotiator.for_accept("application/json")
      expect(serializer).to eq(Whoosh::Serialization::Json)
    end

    it "returns JSON serializer for */*" do
      serializer = Whoosh::Serialization::Negotiator.for_accept("*/*")
      expect(serializer).to eq(Whoosh::Serialization::Json)
    end

    it "returns JSON serializer when no Accept header" do
      serializer = Whoosh::Serialization::Negotiator.for_accept(nil)
      expect(serializer).to eq(Whoosh::Serialization::Json)
    end
  end

  describe ".for_content_type" do
    it "returns JSON deserializer for application/json" do
      deserializer = Whoosh::Serialization::Negotiator.for_content_type("application/json")
      expect(deserializer).to eq(Whoosh::Serialization::Json)
    end

    it "defaults to JSON for unknown types" do
      deserializer = Whoosh::Serialization::Negotiator.for_content_type("text/plain")
      expect(deserializer).to eq(Whoosh::Serialization::Json)
    end
  end
end
```

- [ ] **Step 6: Run negotiator test to verify it fails**

Run: `bundle exec rspec spec/whoosh/serialization/negotiator_spec.rb`
Expected: FAIL

- [ ] **Step 7: Write Negotiator**

```ruby
# lib/whoosh/serialization/negotiator.rb
# frozen_string_literal: true

module Whoosh
  module Serialization
    class Negotiator
      SERIALIZERS = {
        "application/json" => -> { Json }
      }.freeze

      def self.for_accept(accept_header)
        return Json if accept_header.nil? || accept_header.empty?

        accept_header.split(",").each do |media_type|
          type = media_type.strip.split(";").first.strip
          return Json if type == "*/*"

          serializer = SERIALIZERS[type]
          return serializer.call if serializer
        end

        Json # fallback
      end

      def self.for_content_type(content_type)
        return Json if content_type.nil? || content_type.empty?

        type = content_type.split(";").first.strip
        serializer = SERIALIZERS[type]
        serializer ? serializer.call : Json
      end
    end
  end
end
```

- [ ] **Step 8: Run negotiator test to verify it passes**

Run: `bundle exec rspec spec/whoosh/serialization/negotiator_spec.rb`
Expected: All pass

- [ ] **Step 9: Commit**

```bash
git add lib/whoosh/serialization/ spec/whoosh/serialization/
git commit -m "feat: add JSON serialization engine and content negotiator"
```

---

## Chunk 4: Middleware, DI, Logging

### Task 10: Middleware Stack

**Files:**
- Create: `lib/whoosh/middleware/stack.rb`
- Create: `lib/whoosh/middleware/security_headers.rb`
- Create: `lib/whoosh/middleware/cors.rb`
- Create: `lib/whoosh/middleware/request_limit.rb`
- Create: `lib/whoosh/middleware/request_logger.rb`
- Test: `spec/whoosh/middleware/stack_spec.rb`
- Test: `spec/whoosh/middleware/security_headers_spec.rb`
- Test: `spec/whoosh/middleware/cors_spec.rb`
- Test: `spec/whoosh/middleware/request_limit_spec.rb`

- [ ] **Step 1: Write the failing test for middleware stack**

```ruby
# spec/whoosh/middleware/stack_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Middleware::Stack do
  let(:inner_app) { ->(env) { [200, { "content-type" => "text/plain" }, ["OK"]] } }

  describe "#use" do
    it "adds middleware to the stack" do
      stack = Whoosh::Middleware::Stack.new
      test_middleware = Class.new do
        def initialize(app)
          @app = app
        end

        def call(env)
          status, headers, body = @app.call(env)
          headers["x-test"] = "true"
          [status, headers, body]
        end
      end

      stack.use(test_middleware)
      app = stack.build(inner_app)

      env = Rack::MockRequest.env_for("/test")
      status, headers, = app.call(env)

      expect(status).to eq(200)
      expect(headers["x-test"]).to eq("true")
    end
  end

  describe "#build" do
    it "wraps the app with middleware in order" do
      stack = Whoosh::Middleware::Stack.new
      app = stack.build(inner_app)

      env = Rack::MockRequest.env_for("/test")
      status, _, body = app.call(env)
      expect(status).to eq(200)
      expect(body).to eq(["OK"])
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/middleware/stack_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write Stack implementation**

```ruby
# lib/whoosh/middleware/stack.rb
# frozen_string_literal: true

module Whoosh
  module Middleware
    class Stack
      def initialize
        @middlewares = []
      end

      def use(middleware, *args, **kwargs)
        @middlewares << { klass: middleware, args: args, kwargs: kwargs }
      end

      def build(app)
        @middlewares.reverse.reduce(app) do |next_app, entry|
          if entry[:kwargs].empty?
            entry[:klass].new(next_app, *entry[:args])
          else
            entry[:klass].new(next_app, *entry[:args], **entry[:kwargs])
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run stack test to verify it passes**

Run: `bundle exec rspec spec/whoosh/middleware/stack_spec.rb`
Expected: All pass

- [ ] **Step 5: Write failing test for SecurityHeaders**

```ruby
# spec/whoosh/middleware/security_headers_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Middleware::SecurityHeaders do
  let(:inner_app) { ->(env) { [200, {}, ["OK"]] } }
  let(:app) { Whoosh::Middleware::SecurityHeaders.new(inner_app) }

  it "adds X-Content-Type-Options" do
    env = Rack::MockRequest.env_for("/test")
    _, headers, _ = app.call(env)
    expect(headers["x-content-type-options"]).to eq("nosniff")
  end

  it "adds X-Frame-Options" do
    env = Rack::MockRequest.env_for("/test")
    _, headers, _ = app.call(env)
    expect(headers["x-frame-options"]).to eq("DENY")
  end

  it "adds X-XSS-Protection" do
    env = Rack::MockRequest.env_for("/test")
    _, headers, _ = app.call(env)
    expect(headers["x-xss-protection"]).to eq("1; mode=block")
  end

  it "adds Strict-Transport-Security" do
    env = Rack::MockRequest.env_for("/test")
    _, headers, _ = app.call(env)
    expect(headers["strict-transport-security"]).to eq("max-age=31536000; includeSubDomains")
  end
end
```

- [ ] **Step 6: Write SecurityHeaders**

```ruby
# lib/whoosh/middleware/security_headers.rb
# frozen_string_literal: true

module Whoosh
  module Middleware
    class SecurityHeaders
      HEADERS = {
        "x-content-type-options" => "nosniff",
        "x-frame-options" => "DENY",
        "x-xss-protection" => "1; mode=block",
        "strict-transport-security" => "max-age=31536000; includeSubDomains",
        "x-download-options" => "noopen",
        "x-permitted-cross-domain-policies" => "none",
        "referrer-policy" => "strict-origin-when-cross-origin"
      }.freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)
        [status, HEADERS.merge(headers), body]
      end
    end
  end
end
```

- [ ] **Step 7: Run security headers test**

Run: `bundle exec rspec spec/whoosh/middleware/security_headers_spec.rb`
Expected: All pass

- [ ] **Step 8: Write failing test for CORS**

```ruby
# spec/whoosh/middleware/cors_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Middleware::Cors do
  let(:inner_app) { ->(env) { [200, {}, ["OK"]] } }

  describe "with default config" do
    let(:app) { Whoosh::Middleware::Cors.new(inner_app) }

    it "adds CORS headers" do
      env = Rack::MockRequest.env_for("/test", "HTTP_ORIGIN" => "http://example.com")
      _, headers, _ = app.call(env)
      expect(headers["access-control-allow-origin"]).to eq("*")
    end

    it "handles preflight OPTIONS request" do
      env = Rack::MockRequest.env_for("/test",
        method: "OPTIONS",
        "HTTP_ORIGIN" => "http://example.com",
        "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "POST"
      )
      status, headers, _ = app.call(env)
      expect(status).to eq(204)
      expect(headers["access-control-allow-methods"]).to include("POST")
    end
  end

  describe "with custom origins" do
    let(:app) { Whoosh::Middleware::Cors.new(inner_app, origins: ["http://myapp.com"]) }

    it "allows specified origin" do
      env = Rack::MockRequest.env_for("/test", "HTTP_ORIGIN" => "http://myapp.com")
      _, headers, _ = app.call(env)
      expect(headers["access-control-allow-origin"]).to eq("http://myapp.com")
    end

    it "denies unspecified origin" do
      env = Rack::MockRequest.env_for("/test", "HTTP_ORIGIN" => "http://evil.com")
      _, headers, _ = app.call(env)
      expect(headers["access-control-allow-origin"]).to be_nil
    end
  end
end
```

- [ ] **Step 9: Write CORS middleware**

```ruby
# lib/whoosh/middleware/cors.rb
# frozen_string_literal: true

module Whoosh
  module Middleware
    class Cors
      DEFAULT_METHODS = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
      DEFAULT_HEADERS = "Content-Type, Authorization, X-API-Key, X-Request-ID"

      def initialize(app, origins: ["*"], methods: DEFAULT_METHODS, headers: DEFAULT_HEADERS, max_age: 86_400)
        @app = app
        @origins = origins
        @methods = methods
        @headers = headers
        @max_age = max_age
      end

      def call(env)
        origin = env["HTTP_ORIGIN"]

        if env["REQUEST_METHOD"] == "OPTIONS"
          return preflight_response(origin)
        end

        status, headers, body = @app.call(env)
        add_cors_headers(headers, origin)
        [status, headers, body]
      end

      private

      def preflight_response(origin)
        headers = {
          "access-control-allow-methods" => @methods,
          "access-control-allow-headers" => @headers,
          "access-control-max-age" => @max_age.to_s
        }
        add_cors_headers(headers, origin)
        [204, headers, []]
      end

      def add_cors_headers(headers, origin)
        allowed = allowed_origin(origin)
        return unless allowed

        headers["access-control-allow-origin"] = allowed
        headers["access-control-expose-headers"] = "X-Request-ID"
        headers["vary"] = "Origin"
      end

      def allowed_origin(origin)
        return nil unless origin

        if @origins.include?("*")
          "*"
        elsif @origins.include?(origin)
          origin
        end
      end
    end
  end
end
```

- [ ] **Step 10: Run CORS test**

Run: `bundle exec rspec spec/whoosh/middleware/cors_spec.rb`
Expected: All pass

- [ ] **Step 11: Write failing test for RequestLimit**

```ruby
# spec/whoosh/middleware/request_limit_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Middleware::RequestLimit do
  let(:inner_app) { ->(env) { [200, {}, ["OK"]] } }

  it "passes requests under the limit" do
    app = Whoosh::Middleware::RequestLimit.new(inner_app, max_bytes: 1_048_576)
    env = Rack::MockRequest.env_for("/test", method: "POST", input: "small body")
    status, _, _ = app.call(env)
    expect(status).to eq(200)
  end

  it "rejects requests over the limit" do
    app = Whoosh::Middleware::RequestLimit.new(inner_app, max_bytes: 10)
    env = Rack::MockRequest.env_for("/test", method: "POST", input: "x" * 100)
    status, _, body = app.call(env)
    expect(status).to eq(413)
    parsed = JSON.parse(body.first)
    expect(parsed["error"]).to eq("request_too_large")
  end
end
```

- [ ] **Step 12: Write RequestLimit**

```ruby
# lib/whoosh/middleware/request_limit.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module Middleware
    class RequestLimit
      def initialize(app, max_bytes: 1_048_576) # 1MB default
        @app = app
        @max_bytes = max_bytes
      end

      def call(env)
        content_length = env["CONTENT_LENGTH"]&.to_i || 0

        if content_length > @max_bytes
          return [
            413,
            { "content-type" => "application/json" },
            [JSON.generate({ error: "request_too_large", max_bytes: @max_bytes })]
          ]
        end

        @app.call(env)
      end
    end
  end
end
```

- [ ] **Step 13: Run RequestLimit test**

Run: `bundle exec rspec spec/whoosh/middleware/request_limit_spec.rb`
Expected: All pass

- [ ] **Step 14: Commit all middleware**

```bash
git add lib/whoosh/middleware/ spec/whoosh/middleware/
git commit -m "feat: add middleware stack with security headers, CORS, and request limits"
```

---

### Task 11: Dependency Injection

**Files:**
- Create: `lib/whoosh/dependency_injection.rb`
- Test: `spec/whoosh/dependency_injection_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/dependency_injection_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::DependencyInjection do
  let(:di) { Whoosh::DependencyInjection.new }

  describe "#provide (singleton)" do
    it "registers and resolves a singleton dependency" do
      call_count = 0
      di.provide(:db) { call_count += 1; "connection" }

      expect(di.resolve(:db)).to eq("connection")
      expect(di.resolve(:db)).to eq("connection")
      expect(call_count).to eq(1) # Only called once
    end
  end

  describe "#provide (request scope)" do
    it "registers a request-scoped dependency" do
      call_count = 0
      di.provide(:current_user, scope: :request) { |req| call_count += 1; "user_#{req}" }

      expect(di.resolve(:current_user, request: "req1")).to eq("user_req1")
      expect(di.resolve(:current_user, request: "req2")).to eq("user_req2")
      expect(call_count).to eq(2) # Called each time
    end
  end

  describe "dependency chains" do
    it "resolves dependencies that depend on other dependencies" do
      di.provide(:config) { { host: "localhost" } }
      di.provide(:db) { |config:| "db://#{config[:host]}" }

      expect(di.resolve(:db)).to eq("db://localhost")
    end
  end

  describe "circular dependency detection" do
    it "raises DependencyError on circular deps at boot via validate!" do
      di.provide(:a) { |b:| b }
      di.provide(:b) { |a:| a }

      expect { di.validate! }.to raise_error(Whoosh::Errors::DependencyError, /circular/i)
    end

    it "also raises at runtime if resolve is called without validate!" do
      di.provide(:a) { |b:| b }
      di.provide(:b) { |a:| a }

      expect { di.resolve(:a) }.to raise_error(Whoosh::Errors::DependencyError, /circular/i)
    end
  end

  describe "#validate!" do
    it "succeeds for valid dependency graph" do
      di.provide(:config) { { host: "localhost" } }
      di.provide(:db) { |config:| "db://#{config[:host]}" }

      expect { di.validate! }.not_to raise_error
    end

    it "raises for unknown dependency references" do
      di.provide(:db) { |config:| "db://#{config[:host]}" }

      expect { di.validate! }.to raise_error(Whoosh::Errors::DependencyError, /unknown.*config/i)
    end
  end

  describe "#close_all" do
    it "calls close on singletons that respond to it" do
      closeable = double("closeable", close: nil)
      di.provide(:conn) { closeable }
      di.resolve(:conn) # Initialize it

      expect(closeable).to receive(:close)
      di.close_all
    end
  end

  describe "#inject_for" do
    it "returns hash of resolved dependencies for given keyword names" do
      di.provide(:db) { "connection" }
      di.provide(:cache) { "redis" }

      result = di.inject_for([:db, :cache])
      expect(result).to eq({ db: "connection", cache: "redis" })
    end

    it "returns empty hash for empty list" do
      expect(di.inject_for([])).to eq({})
    end
  end

  describe "override" do
    it "allows app.provide to override plugins" do
      di.provide(:db) { "original" }
      di.provide(:db) { "overridden" }

      expect(di.resolve(:db)).to eq("overridden")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/dependency_injection_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/dependency_injection.rb
# frozen_string_literal: true

module Whoosh
  class DependencyInjection
    def initialize
      @providers = {}
      @singletons = {}
      @mutex = Mutex.new
    end

    def provide(name, scope: :singleton, &block)
      @providers[name] = { block: block, scope: scope }
      @singletons.delete(name) # Clear cached value on re-register
    end

    def resolve(name, request: nil, resolving: [])
      provider = @providers[name]
      raise Errors::DependencyError, "Unknown dependency: #{name}" unless provider

      if resolving.include?(name)
        raise Errors::DependencyError, "Circular dependency detected: #{(resolving + [name]).join(' -> ')}"
      end

      case provider[:scope]
      when :singleton
        @mutex.synchronize do
          @singletons[name] ||= call_provider(provider[:block], request: request, resolving: resolving + [name])
        end
      when :request
        call_provider(provider[:block], request: request, resolving: resolving + [name])
      end
    end

    def inject_for(names, request: nil)
      names.each_with_object({}) do |name, hash|
        hash[name] = resolve(name, request: request)
      end
    end

    def validate!
      # Topological sort to detect circular deps and unknown refs at boot
      visited = {}
      sorted = []

      visit = ->(name, path) do
        return if visited[name] == :done
        raise Errors::DependencyError, "Circular dependency detected: #{(path + [name]).join(' -> ')}" if visited[name] == :visiting

        provider = @providers[name]
        raise Errors::DependencyError, "Unknown dependency: #{name} (referenced by #{path.last})" unless provider

        visited[name] = :visiting
        deps = extract_deps(provider[:block])
        deps.each { |dep| visit.call(dep, path + [name]) }
        visited[name] = :done
        sorted << name
      end

      @providers.each_key { |name| visit.call(name, []) unless visited[name] }
      sorted
    end

    def registered?(name)
      @providers.key?(name)
    end

    def close_all
      @singletons.each_value do |instance|
        instance.close if instance.respond_to?(:close)
      end
      @singletons.clear
    end

    private

    def extract_deps(block)
      block.parameters
        .select { |type, _| type == :keyreq || type == :key }
        .map(&:last)
    end

    def call_provider(block, request: nil, resolving: [])
      # Inspect block parameters to determine what to inject
      params = block.parameters
      kwargs = params.select { |type, _| type == :keyreq || type == :key }.map(&:last)

      if kwargs.any?
        deps = kwargs.each_with_object({}) do |dep_name, hash|
          hash[dep_name] = resolve(dep_name, request: request, resolving: resolving)
        end
        block.call(**deps)
      elsif params.any? { |type, _| type == :req || type == :opt }
        block.call(request)
      else
        block.call
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/dependency_injection_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/dependency_injection.rb spec/whoosh/dependency_injection_spec.rb
git commit -m "feat: add DI container with singleton/request scopes and circular detection"
```

---

### Task 12: Logger

**Files:**
- Create: `lib/whoosh/logger.rb`
- Create: `lib/whoosh/middleware/request_logger.rb`
- Test: `spec/whoosh/logger_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/logger_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Logger do
  let(:output) { StringIO.new }

  describe "JSON format" do
    let(:logger) { Whoosh::Logger.new(output: output, format: :json, level: :debug) }

    it "logs info messages as JSON" do
      logger.info("test_event", key: "value")
      output.rewind
      line = output.read
      parsed = JSON.parse(line)
      expect(parsed["level"]).to eq("info")
      expect(parsed["event"]).to eq("test_event")
      expect(parsed["key"]).to eq("value")
      expect(parsed["ts"]).to be_a(String)
    end

    it "respects log level" do
      logger = Whoosh::Logger.new(output: output, format: :json, level: :warn)
      logger.info("ignored")
      logger.warn("shown")
      output.rewind
      lines = output.read.strip.split("\n")
      expect(lines.length).to eq(1)
      expect(JSON.parse(lines.first)["level"]).to eq("warn")
    end

    it "supports debug, info, warn, error levels" do
      logger.debug("d")
      logger.info("i")
      logger.warn("w")
      logger.error("e")
      output.rewind
      lines = output.read.strip.split("\n")
      expect(lines.length).to eq(4)
    end
  end

  describe "text format" do
    let(:logger) { Whoosh::Logger.new(output: output, format: :text, level: :info) }

    it "logs as human-readable text" do
      logger.info("request_complete", method: "GET", path: "/health")
      output.rewind
      line = output.read
      expect(line).to include("INFO")
      expect(line).to include("request_complete")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/logger_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write Logger implementation**

```ruby
# lib/whoosh/logger.rb
# frozen_string_literal: true

require "json"

module Whoosh
  class Logger
    LEVELS = { debug: 0, info: 1, warn: 2, error: 3 }.freeze

    def initialize(output: $stdout, format: :json, level: :info)
      @output = output
      @format = format
      @level = LEVELS[level.to_sym] || 1
    end

    def debug(event, **data)
      log(:debug, event, **data)
    end

    def info(event, **data)
      log(:info, event, **data)
    end

    def warn(event, **data)
      log(:warn, event, **data)
    end

    def error(event, **data)
      log(:error, event, **data)
    end

    private

    def log(level, event, **data)
      return if LEVELS[level] < @level

      entry = { ts: Time.now.utc.iso8601, level: level.to_s, event: event }.merge(data)

      case @format
      when :json
        @output.puts(JSON.generate(entry))
      when :text
        @output.puts("[#{entry[:ts]}] #{level.to_s.upcase} #{event} #{data.map { |k, v| "#{k}=#{v}" }.join(' ')}")
      end
    end
  end
end
```

- [ ] **Step 4: Write failing test for RequestLogger middleware**

```ruby
# spec/whoosh/middleware/request_logger_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Middleware::RequestLogger do
  let(:output) { StringIO.new }
  let(:logger) { Whoosh::Logger.new(output: output, format: :json, level: :info) }
  let(:inner_app) { ->(env) { [200, {}, ["OK"]] } }
  let(:app) { Whoosh::Middleware::RequestLogger.new(inner_app, logger: logger) }

  it "logs request method, path, status, and duration" do
    env = Rack::MockRequest.env_for("/test", method: "GET")
    app.call(env)

    output.rewind
    parsed = JSON.parse(output.read)
    expect(parsed["event"]).to eq("request_complete")
    expect(parsed["method"]).to eq("GET")
    expect(parsed["path"]).to eq("/test")
    expect(parsed["status"]).to eq(200)
    expect(parsed["duration_ms"]).to be_a(Numeric)
  end

  it "includes request_id from header" do
    env = Rack::MockRequest.env_for("/test", "HTTP_X_REQUEST_ID" => "abc-123")
    app.call(env)

    output.rewind
    parsed = JSON.parse(output.read)
    expect(parsed["request_id"]).to eq("abc-123")
  end

  it "passes response through unchanged" do
    env = Rack::MockRequest.env_for("/test")
    status, _, body = app.call(env)
    expect(status).to eq(200)
    expect(body).to eq(["OK"])
  end
end
```

- [ ] **Step 5: Run RequestLogger test to verify it fails**

Run: `bundle exec rspec spec/whoosh/middleware/request_logger_spec.rb`
Expected: FAIL

- [ ] **Step 6: Write RequestLogger middleware**

```ruby
# lib/whoosh/middleware/request_logger.rb
# frozen_string_literal: true

module Whoosh
  module Middleware
    class RequestLogger
      def initialize(app, logger:)
        @app = app
        @logger = logger
      end

      def call(env)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        status, headers, body = @app.call(env)

        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

        @logger.info("request_complete",
          method: env["REQUEST_METHOD"],
          path: env["PATH_INFO"],
          status: status,
          duration_ms: duration_ms,
          request_id: env["HTTP_X_REQUEST_ID"]
        )

        [status, headers, body]
      end
    end
  end
end
```

- [ ] **Step 7: Run RequestLogger test to verify it passes**

Run: `bundle exec rspec spec/whoosh/middleware/request_logger_spec.rb`
Expected: All pass

- [ ] **Step 8: Run all logger tests**

Run: `bundle exec rspec spec/whoosh/logger_spec.rb spec/whoosh/middleware/request_logger_spec.rb`
Expected: All pass

- [ ] **Step 9: Commit**

```bash
git add lib/whoosh/logger.rb lib/whoosh/middleware/request_logger.rb spec/whoosh/logger_spec.rb spec/whoosh/middleware/request_logger_spec.rb
git commit -m "feat: add structured Logger and RequestLogger middleware"
```

---

## Chunk 5: App Class, Rack Integration, End-to-End Tests

### Task 13: App Class

**Files:**
- Create: `lib/whoosh/app.rb`
- Test: `spec/whoosh/app_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/app_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

# Test schema for validated endpoints
class GreetRequest < Whoosh::Schema
  field :name, String, required: true, desc: "Name to greet"
  field :greeting, String, default: "Hello"
end

RSpec.describe Whoosh::App do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "basic routing" do
    before do
      application.get "/health" do
        { status: "ok" }
      end
    end

    it "handles GET requests" do
      get "/health"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq({ "status" => "ok" })
    end

    it "returns 404 for unknown routes" do
      get "/missing"
      expect(last_response.status).to eq(404)
      expect(JSON.parse(last_response.body)["error"]).to eq("not_found")
    end

    it "sets JSON content-type" do
      get "/health"
      expect(last_response.content_type).to include("application/json")
    end
  end

  describe "HTTP methods" do
    before do
      application.get("/get")    { { method: "get" } }
      application.post("/post")  { { method: "post" } }
      application.put("/put")    { { method: "put" } }
      application.patch("/patch") { { method: "patch" } }
      application.delete("/del") { { method: "delete" } }
    end

    it "routes GET" do
      get "/get"
      expect(JSON.parse(last_response.body)["method"]).to eq("get")
    end

    it "routes POST" do
      post "/post"
      expect(JSON.parse(last_response.body)["method"]).to eq("post")
    end

    it "routes PUT" do
      put "/put"
      expect(JSON.parse(last_response.body)["method"]).to eq("put")
    end

    it "routes PATCH" do
      patch "/patch"
      expect(JSON.parse(last_response.body)["method"]).to eq("patch")
    end

    it "routes DELETE" do
      delete "/del"
      expect(JSON.parse(last_response.body)["method"]).to eq("delete")
    end
  end

  describe "path params" do
    before do
      application.get "/users/:id" do |req|
        { user_id: req.params[:id] }
      end
    end

    it "extracts path params" do
      get "/users/42"
      expect(JSON.parse(last_response.body)["user_id"]).to eq("42")
    end
  end

  describe "schema validation" do
    before do
      application.post "/greet", request: GreetRequest do |req|
        { message: "#{req.body[:greeting]}, #{req.body[:name]}!" }
      end
    end

    it "validates and processes valid input" do
      post "/greet", { name: "Alice" }.to_json, "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["message"]).to eq("Hello, Alice!")
    end

    it "returns 422 for invalid input" do
      post "/greet", {}.to_json, "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(422)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("validation_failed")
    end
  end

  describe "route groups" do
    before do
      application.group "/api/v1" do
        get "/items" do
          { items: [] }
        end

        post "/items" do |req|
          { created: true }
        end
      end
    end

    it "prefixes routes" do
      get "/api/v1/items"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["items"]).to eq([])
    end

    it "handles POST in groups" do
      post "/api/v1/items"
      expect(last_response.status).to eq(200)
    end
  end

  describe "dependency injection" do
    before do
      application.provide(:greeting) { "Howdy" }

      application.get "/hello/:name" do |req, greeting:|
        { message: "#{greeting}, #{req.params[:name]}!" }
      end
    end

    it "injects dependencies into handlers" do
      get "/hello/Bob"
      expect(JSON.parse(last_response.body)["message"]).to eq("Howdy, Bob!")
    end
  end

  describe "error handling" do
    before do
      application.get "/explode" do
        raise "boom!"
      end

      application.on_error do |error, req|
        { error: "caught", message: error.message }
      end
    end

    it "catches errors and returns JSON" do
      get "/explode"
      expect(last_response.status).to eq(500)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("caught")
      expect(body["message"]).to eq("boom!")
    end
  end

  describe "security headers" do
    before do
      application.get("/test") { { ok: true } }
    end

    it "includes security headers" do
      get "/test"
      expect(last_response.headers["x-content-type-options"]).to eq("nosniff")
      expect(last_response.headers["x-frame-options"]).to eq("DENY")
    end
  end

  describe "#routes" do
    it "lists all registered routes" do
      application.get("/a") { {} }
      application.post("/b") { {} }

      routes = application.routes
      expect(routes.length).to eq(2)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/app_spec.rb`
Expected: FAIL — `cannot load such file -- whoosh/app`

- [ ] **Step 3: Write App implementation**

```ruby
# lib/whoosh/app.rb
# frozen_string_literal: true

require "json"

module Whoosh
  class App
    attr_reader :config, :logger

    def initialize(root: Dir.pwd)
      @config = Config.load(root: root)
      @router = Router.new
      @middleware_stack = Middleware::Stack.new
      @di = DependencyInjection.new
      @error_handlers = {}
      @default_error_handler = nil
      @logger = Whoosh::Logger.new(
        format: @config.log_format.to_sym,
        level: @config.log_level.to_sym
      )
      @group_prefix = ""
      @group_middleware = []

      setup_default_middleware
    end

    # --- HTTP verb methods ---

    def get(path, **opts, &block)
      add_route("GET", path, **opts, &block)
    end

    def post(path, **opts, &block)
      add_route("POST", path, **opts, &block)
    end

    def put(path, **opts, &block)
      add_route("PUT", path, **opts, &block)
    end

    def patch(path, **opts, &block)
      add_route("PATCH", path, **opts, &block)
    end

    def delete(path, **opts, &block)
      add_route("DELETE", path, **opts, &block)
    end

    def options(path, **opts, &block)
      add_route("OPTIONS", path, **opts, &block)
    end

    # --- Route groups ---

    def group(prefix, middleware: [], &block)
      previous_prefix = @group_prefix
      previous_middleware = @group_middleware

      @group_prefix = "#{previous_prefix}#{prefix}"
      @group_middleware = previous_middleware + middleware

      instance_eval(&block)
    ensure
      @group_prefix = previous_prefix
      @group_middleware = previous_middleware
    end

    # --- Dependency injection ---

    def provide(name, scope: :singleton, &block)
      @di.provide(name, scope: scope, &block)
    end

    # --- Error handling ---

    def on_error(exception_class = nil, &block)
      if exception_class
        @error_handlers[exception_class] = block
      else
        @default_error_handler = block
      end
    end

    # --- Route listing ---

    def routes
      @router.routes
    end

    # --- Rack interface ---

    def to_rack
      @rack_app ||= begin
        @di.validate!
        @router.freeze!
        inner = method(:handle_request)
        @middleware_stack.build(inner)
      end
    end

    private

    def setup_default_middleware
      @middleware_stack.use(Middleware::RequestLimit)
      @middleware_stack.use(Middleware::SecurityHeaders)
      @middleware_stack.use(Middleware::Cors)
      @middleware_stack.use(Middleware::RequestLogger, logger: @logger)
    end

    def add_route(method, path, request: nil, response: nil, **metadata, &block)
      full_path = "#{@group_prefix}#{path}"
      handler = {
        block: block,
        request_schema: request,
        response_schema: response,
        middleware: @group_middleware.dup
      }
      @router.add(method, full_path, handler, **metadata)
    end

    def handle_request(env)
      request = Request.new(env)
      match = @router.match(request.method, request.path)

      return Response.not_found unless match

      request.path_params = match[:params]
      handler = match[:handler]

      # Validate request schema
      if handler[:request_schema]
        body = request.body || {}
        result = handler[:request_schema].validate(body)
        unless result.success?
          return Response.error(Errors::ValidationError.new(result.errors))
        end
        request.instance_variable_set(:@body, result.data)
      end

      # Resolve dependencies
      block = handler[:block]
      block_params = block.parameters
      kwargs_names = block_params.select { |type, _| type == :keyreq || type == :key }.map(&:last)
      kwargs = @di.inject_for(kwargs_names, request: request)

      # Call handler
      result = if kwargs.any? && block_params.any? { |type, _| type == :req || type == :opt }
        block.call(request, **kwargs)
      elsif kwargs.any?
        block.call(**kwargs)
      elsif block_params.any? { |type, _| type == :req || type == :opt }
        block.call(request)
      else
        block.call
      end

      Response.json(result)

    rescue Errors::HttpError => e
      Response.error(e)
    rescue => e
      handle_error(e, request)
    end

    def handle_error(error, request)
      # Check specific error handlers
      handler = @error_handlers.find { |klass, _| error.is_a?(klass) }&.last
      handler ||= @default_error_handler

      if handler
        result = handler.call(error, request)
        Response.json(result, status: 500)
      else
        Response.error(error, production: @config.production?)
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/app_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/app.rb spec/whoosh/app_spec.rb
git commit -m "feat: add App class combining router, schema, DI, middleware, and error handling"
```

---

### Task 14: Full Test Suite & Final Verification

**Files:**
- Modify: `spec/spec_helper.rb` (if needed)

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rspec`
Expected: All tests pass (Types, Errors, Config, Request, Response, Router, Schema, Serialization, Middleware, DI, Logger, App)

- [ ] **Step 2: Verify hello-world app works end-to-end**

Create a quick smoke test file (not committed — just for verification):

```bash
bundle exec ruby -e "
require 'whoosh'
require 'rack/test'
include Rack::Test::Methods

app_instance = Whoosh::App.new
app_instance.get('/hello') { { message: 'Hello, Whoosh!' } }
app_instance.get('/users/:id') { |req| { id: req.params[:id] } }

define_method(:app) { app_instance.to_rack }

get '/hello'
puts \"Status: #{last_response.status}\"
puts \"Body: #{last_response.body}\"

get '/users/42'
puts \"User: #{last_response.body}\"

puts 'Whoosh Phase 1 working!'
"
```

Expected:
```
Status: 200
Body: {"message":"Hello, Whoosh!"}
User: {"id":"42"}
Whoosh Phase 1 working!
```

- [ ] **Step 3: Commit final state**

```bash
git status
git add lib/ spec/ whoosh.gemspec Gemfile Gemfile.lock Rakefile .rspec exe/
git commit -m "feat: complete Whoosh Phase 1 — core framework with routing, schema, DI, middleware"
```

---

## Phase 1 Completion Checklist

After all tasks are done, verify:

- [ ] `bundle exec rspec` — all green
- [ ] Trie-based router with path params ✓
- [ ] Schema validation via dry-schema ✓
- [ ] JSON serialization ✓
- [ ] Middleware stack (security headers, CORS, request limits, logging) ✓
- [ ] Dependency injection (singleton + request scope) ✓
- [ ] Error handling with JSON responses ✓
- [ ] Structured logging ✓
- [ ] Config loading (YAML + ENV) ✓
- [ ] Rack-compatible via `to_rack` ✓
- [ ] All modules lazy-loaded via `autoload` ✓

## Next Phase

After Phase 1 passes, proceed to **Phase 2: Plugin System & Endpoints** — adding auto-discovery, class-based endpoints, and plugin adapters.
