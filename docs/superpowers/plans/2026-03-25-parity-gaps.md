# FastAPI Parity Gaps Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close 10 feature gaps with FastAPI to reach ~90% parity. All changes follow Whoosh philosophy: zero-config defaults, secure by default, minimal API surface.

**Architecture:** Small targeted additions to existing modules. No new hard dependencies. Each gap is independent — can be implemented in any order.

**Tech Stack:** Ruby 3.4+, RSpec. No new gems.

**Depends on:** v1.4.1 (542 tests passing).

---

## Chunk 1: Quick Wins (Gaps 1, 2, 6, 7, 9, 10)

### Task 1: Cookie Helpers + Redirect + Download + Static Files

**Files:**
- Modify: `lib/whoosh/response.rb`
- Modify: `lib/whoosh/request.rb`
- Modify: `lib/whoosh/app.rb`
- Test: `spec/whoosh/helpers_spec.rb`

Add to `Response`:
```ruby
def self.redirect(url, status: 302)
  [status, { "location" => url }, []]
end

def self.download(data, filename:, content_type: "application/octet-stream")
  [200, {
    "content-type" => content_type,
    "content-disposition" => "attachment; filename=\"#{filename}\""
  }, [data]]
end

def self.file(path, content_type: nil)
  raise Errors::NotFoundError unless File.exist?(path)
  ct = content_type || guess_content_type(path)
  body = File.binread(path)
  [200, { "content-type" => ct, "content-length" => body.bytesize.to_s }, [body]]
end

MIME_TYPES = { ".html" => "text/html", ".json" => "application/json", ".css" => "text/css",
  ".js" => "application/javascript", ".png" => "image/png", ".jpg" => "image/jpeg",
  ".svg" => "image/svg+xml", ".pdf" => "application/pdf", ".txt" => "text/plain" }.freeze

def self.guess_content_type(path)
  ext = File.extname(path).downcase
  MIME_TYPES[ext] || "application/octet-stream"
end
```

Add to `Request`:
```ruby
def cookies
  @cookies ||= begin
    raw = @env["HTTP_COOKIE"] || ""
    raw.split(";").each_with_object({}) do |pair, h|
      k, v = pair.strip.split("=", 2)
      h[k] = v if k
    end
  end
end
```

Add to `App` (public helpers):
```ruby
def redirect(url, status: 302)
  Response.redirect(url, status: status)
end

def download(data, filename:, content_type: nil)
  Response.download(data, filename: filename, content_type: content_type || "application/octet-stream")
end

def send_file(path, content_type: nil)
  Response.file(path, content_type: content_type)
end

# Static file serving from a directory
def serve_static(prefix, root:)
  get "#{prefix}/*path" do |req|
    file_path = File.join(root, req.params[:path])
    # Prevent directory traversal
    real = File.realpath(file_path) rescue nil
    real_root = File.realpath(root) rescue root
    if real && real.start_with?(real_root) && File.file?(real)
      Response.file(real)
    else
      Response.not_found
    end
  end
end
```

Test:
```ruby
# spec/whoosh/helpers_spec.rb
RSpec.describe "Response helpers" do
  include Rack::Test::Methods
  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "redirect" do
    before { application.get("/old") { redirect("/new") } }
    it "returns 302 with location" do
      get "/old"
      expect(last_response.status).to eq(302)
      expect(last_response.headers["location"]).to eq("/new")
    end
  end

  describe "cookies" do
    before do
      application.get("/cookie") do |req|
        { token: req.cookies["session"] }
      end
    end
    it "reads cookies from request" do
      get "/cookie", {}, { "HTTP_COOKIE" => "session=abc123" }
      expect(JSON.parse(last_response.body)["token"]).to eq("abc123")
    end
  end

  describe "download" do
    before { application.get("/dl") { download("file content", filename: "report.csv") } }
    it "returns attachment header" do
      get "/dl"
      expect(last_response.headers["content-disposition"]).to include("report.csv")
    end
  end

  describe "Response.file" do
    it "serves a file" do
      require "tmpdir"
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "test.txt"), "hello")
        status, headers, body = Whoosh::Response.file(File.join(dir, "test.txt"))
        expect(status).to eq(200)
        expect(headers["content-type"]).to eq("text/plain")
        expect(body.first).to eq("hello")
      end
    end

    it "returns 404 for missing file" do
      expect { Whoosh::Response.file("/nonexistent") }.to raise_error(Whoosh::Errors::NotFoundError)
    end
  end
end
```

Commit: `feat: add cookie, redirect, download, and static file helpers`

---

### Task 2: CSP Header + Middleware Error Handling

**Files:**
- Modify: `lib/whoosh/middleware/security_headers.rb`
- Modify: `lib/whoosh/app.rb` (compiled handler)
- Test: `spec/whoosh/security_spec.rb`

Add CSP to SecurityHeaders:
```ruby
HEADERS = {
  "x-content-type-options" => "nosniff",
  "x-frame-options" => "DENY",
  "x-xss-protection" => "1; mode=block",
  "strict-transport-security" => "max-age=31536000; includeSubDomains",
  "x-download-options" => "noopen",
  "x-permitted-cross-domain-policies" => "none",
  "referrer-policy" => "strict-origin-when-cross-origin",
  "content-security-policy" => "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
}.freeze
```

Add middleware error handling in compiled handler — wrap the entire lambda body in rescue:

In `build_compiled_handler`, after the `-> (env) {` opening:
```ruby
      begin
        # ... existing code ...
      rescue => e
        # Middleware-level error — return 500 JSON
        [500, { "content-type" => "application/json" },
          [JSON.generate({ error: "internal_error", message: e.message })]]
      end
```

Test:
```ruby
# spec/whoosh/security_spec.rb
RSpec.describe "Security headers" do
  include Rack::Test::Methods
  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  before { application.get("/test") { { ok: true } } }

  it "includes CSP header" do
    get "/test"
    expect(last_response.headers["content-security-policy"]).to include("default-src")
  end

  it "includes all security headers" do
    get "/test"
    %w[x-content-type-options x-frame-options strict-transport-security referrer-policy content-security-policy].each do |h|
      expect(last_response.headers[h]).not_to be_nil, "Missing header: #{h}"
    end
  end
end
```

Commit: `feat: add CSP header and middleware error handling`

---

## Chunk 2: Validation + OpenAPI (Gaps 3, 5)

### Task 3: Custom Schema Validators

**Files:**
- Modify: `lib/whoosh/schema.rb`
- Test: `spec/whoosh/custom_validators_spec.rb`

Add `validate` block DSL to Schema:
```ruby
class CreateUserSchema < Whoosh::Schema
  field :email, String, required: true
  field :age, Integer, min: 0

  validate do |data, errors|
    if data[:email] && !data[:email].include?("@")
      errors << { field: :email, message: "must be a valid email" }
    end
    if data[:age] && data[:age] < 18
      errors << { field: :age, message: "must be at least 18" }
    end
  end
end
```

Implementation — add to Schema class:
```ruby
class << self
  def validate_with(&block)
    @custom_validators ||= []
    @custom_validators << block
  end
  alias_method :validate_block, :validate_with

  def custom_validators
    @custom_validators || []
  end
end
```

In `validate` method, after the second pass (min/max), run custom validators:
```ruby
# Third pass: custom validators
self.custom_validators.each do |validator|
  validator.call(validated, errors)
end
```

Commit: `feat: add custom schema validators via validate block DSL`

---

### Task 4: Query Param Docs in OpenAPI

**Files:**
- Modify: `lib/whoosh/openapi/generator.rb`
- Modify: `lib/whoosh/app.rb` (pass query param info to generator)
- Test: `spec/whoosh/openapi/query_params_spec.rb`

Add query param support to route registration. When a schema has non-required fields and the route is GET, treat them as query params in OpenAPI:

In `Generator#add_route`, add `query_params:` parameter:
```ruby
def add_route(method:, path:, request_schema: nil, response_schema: nil, query_schema: nil, description: nil)
  # ... existing code ...

  # Query parameters from schema
  if query_schema
    schema_data = SchemaConverter.convert(query_schema)
    (schema_data[:properties] || {}).each do |name, prop|
      operation[:parameters] ||= []
      operation[:parameters] << {
        name: name.to_s, in: "query", required: schema_data[:required]&.include?(name) || false,
        schema: prop, description: prop[:description]
      }
    end
  end
end
```

Add `query:` option to route DSL:
```ruby
app.get "/users", query: UserFilterSchema do |req|
  # req.query_params available as usual
end
```

Commit: `feat: add query param documentation in OpenAPI spec`

---

## Chunk 3: OAuth2 + Async HTTP (Gaps 4, 8)

### Task 5: OAuth2 Provider Flows

**Files:**
- Modify: `lib/whoosh/auth/oauth2.rb`
- Test: `spec/whoosh/auth/oauth2_full_spec.rb`

Implement the three common OAuth2 flows:
1. **Authorization Code** (Google/GitHub login)
2. **Client Credentials** (service-to-service)
3. **Token validation** (already exists)

```ruby
class OAuth2
  def initialize(provider: :custom, client_id: nil, client_secret: nil,
                 authorize_url: nil, token_url: nil, userinfo_url: nil,
                 redirect_uri: nil, scopes: [], validator: nil)
    @provider = provider
    @client_id = client_id
    @client_secret = client_secret
    @authorize_url = authorize_url
    @token_url = token_url
    @userinfo_url = userinfo_url
    @redirect_uri = redirect_uri
    @scopes = scopes
    @validator = validator

    apply_provider_defaults if PROVIDERS[@provider]
  end

  PROVIDERS = {
    google: {
      authorize_url: "https://accounts.google.com/o/oauth2/v2/auth",
      token_url: "https://oauth2.googleapis.com/token",
      userinfo_url: "https://www.googleapis.com/oauth2/v3/userinfo"
    },
    github: {
      authorize_url: "https://github.com/login/oauth/authorize",
      token_url: "https://github.com/login/oauth/access_token",
      userinfo_url: "https://api.github.com/user"
    }
  }.freeze

  # Generate authorization URL for redirect
  def authorize_url(state: SecureRandom.hex(16))
    params = {
      client_id: @client_id,
      redirect_uri: @redirect_uri,
      response_type: "code",
      scope: @scopes.join(" "),
      state: state
    }
    "#{@authorize_url}?#{URI.encode_www_form(params)}"
  end

  # Exchange authorization code for tokens
  def exchange_code(code)
    response = HTTP.post(@token_url, json: {
      client_id: @client_id,
      client_secret: @client_secret,
      code: code,
      redirect_uri: @redirect_uri,
      grant_type: "authorization_code"
    }, headers: { "Accept" => "application/json" })

    raise Errors::UnauthorizedError, "Token exchange failed" unless response.ok?
    response.json
  end

  # Get user info from access token
  def userinfo(access_token)
    response = HTTP.get(@userinfo_url, headers: {
      "Authorization" => "Bearer #{access_token}",
      "Accept" => "application/json"
    })
    raise Errors::UnauthorizedError, "Userinfo request failed" unless response.ok?
    response.json
  end

  # Authenticate from request (validate Bearer token)
  def authenticate(request)
    auth_header = request.headers["Authorization"]
    raise Errors::UnauthorizedError, "Missing authorization" unless auth_header
    token = auth_header.sub(/\ABearer\s+/i, "")
    raise Errors::UnauthorizedError, "Missing token" if token.empty?

    if @validator
      result = @validator.call(token)
      raise Errors::UnauthorizedError, "Invalid token" unless result
      result
    elsif @userinfo_url
      userinfo(token)
    else
      { token: token }
    end
  end

  private

  def apply_provider_defaults
    defaults = PROVIDERS[@provider]
    @authorize_url ||= defaults[:authorize_url]
    @token_url ||= defaults[:token_url]
    @userinfo_url ||= defaults[:userinfo_url]
  end
end
```

Wire into AuthBuilder:
```ruby
def oauth2(provider: :custom, **opts)
  @strategies[:oauth2] = Auth::OAuth2.new(provider: provider, **opts)
end
```

Commit: `feat: add OAuth2 with Google/GitHub provider support`

---

### Task 6: Async HTTP Client

**Files:**
- Modify: `lib/whoosh/http.rb`
- Test: `spec/whoosh/http_async_spec.rb`

Add `async` versions using Thread pool for concurrent requests:
```ruby
# Concurrent requests — run multiple HTTP calls in parallel
def self.concurrent(*requests)
  threads = requests.map do |req|
    Thread.new { send(req[:method], req[:url], **req.except(:method, :url)) }
  end
  threads.map(&:value)
end

# Async single request — returns a Future-like object
def self.async
  AsyncClient.new
end

class AsyncClient
  def get(url, **opts)
    Thread.new { HTTP.get(url, **opts) }
  end

  def post(url, **opts)
    Thread.new { HTTP.post(url, **opts) }
  end
  # ... put, patch, delete
end
```

Usage:
```ruby
# Concurrent requests
results = Whoosh::HTTP.concurrent(
  { method: :get, url: "https://api.a.com/data" },
  { method: :get, url: "https://api.b.com/data" }
)

# Async single
future = Whoosh::HTTP.async.get("https://api.example.com/slow")
# ... do other work ...
response = future.value  # blocks until complete
```

Commit: `feat: add concurrent and async HTTP requests via thread pool`

---

## Completion Checklist

- [ ] `bundle exec rspec` — all green
- [ ] Gap 1: Cookie helpers (read from request)
- [ ] Gap 2: Redirect helper (`redirect(url)`)
- [ ] Gap 3: Query param docs in OpenAPI
- [ ] Gap 4: OAuth2 with Google/GitHub providers
- [ ] Gap 5: Custom schema validators (`validate` block)
- [ ] Gap 6: Static file serving (`serve_static`)
- [ ] Gap 7: Download helper (`download(data, filename:)`)
- [ ] Gap 8: Async HTTP client (concurrent + async)
- [ ] Gap 9: CSP header in security defaults
- [ ] Gap 10: Middleware error handling (rescue in compiled handler)
- [ ] All existing tests still pass
- [ ] Version bump + gem publish + GitHub release
