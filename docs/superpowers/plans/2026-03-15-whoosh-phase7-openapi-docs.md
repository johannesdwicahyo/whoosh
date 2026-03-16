# Whoosh Phase 7: OpenAPI & Docs Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-generate OpenAPI 3.1 specs from routes and schemas, serve Swagger UI at `/docs`, and provide `/openapi.json` endpoint. Zero manual annotations needed.

**Architecture:** `SchemaConverter` converts `Whoosh::Schema` fields to OpenAPI 3.1 schema objects. `Generator` walks all registered routes, extracts request/response schemas, and builds a complete OpenAPI spec. `UI` renders a simple Swagger UI HTML page. App registers `/openapi.json` and `/docs` routes automatically when docs are enabled.

**Tech Stack:** Ruby 3.4+, RSpec, rack-test. No external gems — Swagger UI is a single inline HTML page using CDN.

**Spec:** `docs/superpowers/specs/2026-03-11-whoosh-design.md` (OpenAPI section lines 672-693)

**Depends on:** Phase 1-6 complete (235 tests passing). Schema, Router, Config all working.

---

## Chunk 1: Schema Converter and Generator

### Task 1: OpenAPI Schema Converter

**Files:**
- Create: `lib/whoosh/openapi/schema_converter.rb`
- Test: `spec/whoosh/openapi/schema_converter_spec.rb`

Converts `Whoosh::Schema` subclasses to OpenAPI 3.1 schema objects.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/openapi/schema_converter_spec.rb
# frozen_string_literal: true

require "spec_helper"

class OpenAPITestSchema < Whoosh::Schema
  field :name,        String,  required: true, desc: "User name"
  field :email,       String,  required: true
  field :age,         Integer, min: 0, max: 150
  field :temperature, Float,   default: 0.7
  field :active,      Whoosh::Types::Bool, default: true
end

class OpenAPINestedSchema < Whoosh::Schema
  field :user,    OpenAPITestSchema, required: true
  field :comment, String
end

RSpec.describe Whoosh::OpenAPI::SchemaConverter do
  describe ".convert" do
    it "converts a schema to OpenAPI format" do
      result = Whoosh::OpenAPI::SchemaConverter.convert(OpenAPITestSchema)
      expect(result[:type]).to eq("object")
      expect(result[:properties][:name][:type]).to eq("string")
      expect(result[:properties][:name][:description]).to eq("User name")
      expect(result[:required]).to include(:name, :email)
    end

    it "includes integer type with min/max" do
      result = Whoosh::OpenAPI::SchemaConverter.convert(OpenAPITestSchema)
      age = result[:properties][:age]
      expect(age[:type]).to eq("integer")
      expect(age[:minimum]).to eq(0)
      expect(age[:maximum]).to eq(150)
    end

    it "includes float type with default" do
      result = Whoosh::OpenAPI::SchemaConverter.convert(OpenAPITestSchema)
      temp = result[:properties][:temperature]
      expect(temp[:type]).to eq("number")
      expect(temp[:default]).to eq(0.7)
    end

    it "converts boolean type" do
      result = Whoosh::OpenAPI::SchemaConverter.convert(OpenAPITestSchema)
      expect(result[:properties][:active][:type]).to eq("boolean")
    end

    it "handles nested schemas" do
      result = Whoosh::OpenAPI::SchemaConverter.convert(OpenAPINestedSchema)
      user_prop = result[:properties][:user]
      expect(user_prop[:type]).to eq("object")
      expect(user_prop[:properties][:name][:type]).to eq("string")
    end
  end

  describe ".type_for" do
    it "maps Ruby types to OpenAPI types" do
      expect(Whoosh::OpenAPI::SchemaConverter.type_for(String)).to eq("string")
      expect(Whoosh::OpenAPI::SchemaConverter.type_for(Integer)).to eq("integer")
      expect(Whoosh::OpenAPI::SchemaConverter.type_for(Float)).to eq("number")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/openapi/schema_converter.rb
# frozen_string_literal: true

module Whoosh
  module OpenAPI
    class SchemaConverter
      TYPE_MAP = {
        "String"   => "string",
        "Integer"  => "integer",
        "Float"    => "number",
        "Hash"     => "object",
        "Array"    => "array",
        "Time"     => "string",
        "DateTime" => "string"
      }.freeze

      def self.convert(schema_class)
        return {} unless schema_class.respond_to?(:fields)

        properties = {}
        required = []

        schema_class.fields.each do |name, opts|
          type = opts[:type]

          if type.is_a?(Class) && type < Schema
            properties[name] = convert(type)
          else
            prop = { type: type_for(type) }
            prop[:description] = opts[:desc] if opts[:desc]
            prop[:default] = opts[:default] if opts.key?(:default)
            prop[:minimum] = opts[:min] if opts[:min]
            prop[:maximum] = opts[:max] if opts[:max]
            prop[:format] = "date-time" if type == Time || type == DateTime
            properties[name] = prop
          end

          required << name if opts[:required]
        end

        result = { type: "object", properties: properties }
        result[:required] = required unless required.empty?
        result
      end

      def self.type_for(type)
        return "boolean" if type.respond_to?(:ancestors) rescue false
        return "boolean" if type.is_a?(Dry::Types::Type) rescue false

        TYPE_MAP[type.to_s] || "string"
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/openapi/schema_converter.rb spec/whoosh/openapi/schema_converter_spec.rb
git commit -m "feat: add OpenAPI SchemaConverter for Whoosh::Schema to OpenAPI 3.1 mapping"
```

---

### Task 2: OpenAPI Generator

**Files:**
- Create: `lib/whoosh/openapi/generator.rb`
- Test: `spec/whoosh/openapi/generator_spec.rb`

Generates a complete OpenAPI 3.1 spec from routes.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/openapi/generator_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::OpenAPI::Generator do
  let(:generator) { Whoosh::OpenAPI::Generator.new(title: "Test API", version: "1.0.0") }

  describe "#add_route" do
    it "adds a route to the spec" do
      generator.add_route(method: "GET", path: "/health")
      spec = generator.generate
      expect(spec[:paths]["/health"][:get]).not_to be_nil
    end

    it "includes request schema" do
      schema_class = Class.new(Whoosh::Schema) do
        field :name, String, required: true
      end

      generator.add_route(method: "POST", path: "/users", request_schema: schema_class)
      spec = generator.generate
      request_body = spec[:paths]["/users"][:post][:requestBody]
      expect(request_body[:content]["application/json"][:schema][:properties][:name]).not_to be_nil
    end
  end

  describe "#generate" do
    it "produces valid OpenAPI 3.1 structure" do
      generator.add_route(method: "GET", path: "/health")
      spec = generator.generate

      expect(spec[:openapi]).to eq("3.1.0")
      expect(spec[:info][:title]).to eq("Test API")
      expect(spec[:info][:version]).to eq("1.0.0")
      expect(spec[:paths]).to be_a(Hash)
    end

    it "converts path params to OpenAPI format" do
      generator.add_route(method: "GET", path: "/users/:id")
      spec = generator.generate
      expect(spec[:paths]["/users/{id}"]).not_to be_nil
      params = spec[:paths]["/users/{id}"][:get][:parameters]
      expect(params.first[:name]).to eq("id")
      expect(params.first[:in]).to eq("path")
    end
  end

  describe "#to_json" do
    it "serializes to JSON" do
      generator.add_route(method: "GET", path: "/health")
      json = generator.to_json
      parsed = JSON.parse(json)
      expect(parsed["openapi"]).to eq("3.1.0")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/openapi/generator.rb
# frozen_string_literal: true

require "json"

module Whoosh
  module OpenAPI
    class Generator
      def initialize(title: "Whoosh API", version: "0.1.0", description: nil)
        @title = title
        @version = version
        @description = description
        @paths = {}
        @servers = []
      end

      def add_route(method:, path:, request_schema: nil, response_schema: nil, description: nil, tags: [])
        openapi_path = path.gsub(/:(\w+)/, '{\1}')
        http_method = method.downcase.to_sym

        @paths[openapi_path] ||= {}
        operation = {}
        operation[:summary] = description || "#{method} #{path}"
        operation[:tags] = tags unless tags.empty?

        # Path parameters
        params = path.scan(/:(\w+)/).flatten
        unless params.empty?
          operation[:parameters] = params.map do |param|
            { name: param, in: "path", required: true, schema: { type: "string" } }
          end
        end

        # Request body
        if request_schema
          schema = SchemaConverter.convert(request_schema)
          operation[:requestBody] = {
            required: true,
            content: { "application/json" => { schema: schema } }
          }
        end

        # Responses
        operation[:responses] = {
          "200" => {
            description: "Successful response",
            content: { "application/json" => { schema: { type: "object" } } }
          }
        }

        if response_schema
          resp_schema = SchemaConverter.convert(response_schema)
          operation[:responses]["200"][:content]["application/json"][:schema] = resp_schema
        end

        @paths[openapi_path][http_method] = operation
      end

      def add_server(url:, description: nil)
        server = { url: url }
        server[:description] = description if description
        @servers << server
      end

      def generate
        spec = {
          openapi: "3.1.0",
          info: {
            title: @title,
            version: @version
          },
          paths: @paths
        }

        spec[:info][:description] = @description if @description
        spec[:servers] = @servers unless @servers.empty?
        spec
      end

      def to_json
        JSON.generate(generate)
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/openapi/generator.rb spec/whoosh/openapi/generator_spec.rb
git commit -m "feat: add OpenAPI Generator producing 3.1 specs from routes and schemas"
```

---

## Chunk 2: UI and App Integration

### Task 3: Swagger UI

**Files:**
- Create: `lib/whoosh/openapi/ui.rb`
- Test: `spec/whoosh/openapi/ui_spec.rb`

Serves a simple Swagger UI HTML page that loads from CDN.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/openapi/ui_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::OpenAPI::UI do
  describe ".swagger_html" do
    it "returns HTML with Swagger UI" do
      html = Whoosh::OpenAPI::UI.swagger_html("/openapi.json")
      expect(html).to include("swagger-ui")
      expect(html).to include("/openapi.json")
      expect(html).to include("<html")
    end
  end

  describe ".rack_response" do
    it "returns a Rack-compatible response" do
      status, headers, body = Whoosh::OpenAPI::UI.rack_response("/openapi.json")
      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("text/html")
      expect(body.first).to include("swagger-ui")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/openapi/ui.rb
# frozen_string_literal: true

module Whoosh
  module OpenAPI
    class UI
      SWAGGER_CDN = "https://unpkg.com/swagger-ui-dist@5"

      def self.swagger_html(spec_url)
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>API Docs</title>
            <link rel="stylesheet" href="#{SWAGGER_CDN}/swagger-ui.css">
          </head>
          <body>
            <div id="swagger-ui"></div>
            <script src="#{SWAGGER_CDN}/swagger-ui-bundle.js"></script>
            <script>
              SwaggerUIBundle({
                url: "#{spec_url}",
                dom_id: '#swagger-ui',
                presets: [SwaggerUIBundle.presets.apis],
                layout: "BaseLayout"
              });
            </script>
          </body>
          </html>
        HTML
      end

      def self.rack_response(spec_url)
        html = swagger_html(spec_url)
        [200, { "content-type" => "text/html", "content-length" => html.bytesize.to_s }, [html]]
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/openapi/ui.rb spec/whoosh/openapi/ui_spec.rb
git commit -m "feat: add Swagger UI renderer with CDN-based assets"
```

---

### Task 4: App OpenAPI Integration

**Files:**
- Modify: `lib/whoosh/app.rb`
- Test: `spec/whoosh/app_openapi_spec.rb`

Auto-register `/openapi.json` and `/docs` routes. Add `openapi` DSL block.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/app_openapi_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

class DocsTestSchema < Whoosh::Schema
  field :name, String, required: true, desc: "User name"
end

RSpec.describe "App OpenAPI integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "/openapi.json" do
    before do
      application.post "/users", request: DocsTestSchema do |req|
        { created: true }
      end

      application.get "/health" do
        { status: "ok" }
      end
    end

    it "serves OpenAPI 3.1 spec" do
      get "/openapi.json"
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include("application/json")
      spec = JSON.parse(last_response.body)
      expect(spec["openapi"]).to eq("3.1.0")
    end

    it "includes registered routes" do
      get "/openapi.json"
      spec = JSON.parse(last_response.body)
      expect(spec["paths"]).to have_key("/users")
      expect(spec["paths"]).to have_key("/health")
    end

    it "includes request schemas" do
      get "/openapi.json"
      spec = JSON.parse(last_response.body)
      users_post = spec["paths"]["/users"]["post"]
      expect(users_post["requestBody"]).not_to be_nil
    end
  end

  describe "/docs" do
    before do
      application.get "/health" do
        { status: "ok" }
      end
    end

    it "serves Swagger UI HTML" do
      get "/docs"
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include("text/html")
      expect(last_response.body).to include("swagger-ui")
    end
  end

  describe "openapi DSL" do
    it "configures API metadata" do
      application.openapi do
        title "My API"
        version "2.0.0"
        description "Test API"
      end

      application.get "/test" do
        { ok: true }
      end

      get "/openapi.json"
      spec = JSON.parse(last_response.body)
      expect(spec["info"]["title"]).to eq("My API")
      expect(spec["info"]["version"]).to eq("2.0.0")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Update App**

Read `lib/whoosh/app.rb`. Add:

**Add to initialize (after mcp_manager):**
```ruby
      @openapi_config = { title: "Whoosh API", version: Whoosh::VERSION }
```

**Add public method:**
```ruby
    # --- OpenAPI DSL ---

    def openapi(&block)
      builder = OpenAPIConfigBuilder.new
      builder.instance_eval(&block)
      @openapi_config.merge!(builder.to_h)
    end
```

**Update to_rack — add doc routes BEFORE freeze, after register_mcp_tools:**
```ruby
        register_doc_routes if @config.docs_enabled?
```

**Add private methods:**
```ruby
    def register_doc_routes
      generator = OpenAPI::Generator.new(**@openapi_config)

      @router.routes.each do |route|
        match = @router.match(route[:method], route[:path])
        next unless match

        handler = match[:handler]
        generator.add_route(
          method: route[:method],
          path: route[:path],
          request_schema: handler[:request_schema],
          response_schema: handler[:response_schema]
        )
      end

      openapi_json = generator.to_json
      @router.add("GET", "/openapi.json", {
        block: -> (_) { [200, { "content-type" => "application/json" }, [openapi_json]] },
        request_schema: nil, response_schema: nil, middleware: []
      })

      @router.add("GET", "/docs", {
        block: -> (_) { OpenAPI::UI.rack_response("/openapi.json") },
        request_schema: nil, response_schema: nil, middleware: []
      })
    end
```

**Add builder class:**
```ruby
    class OpenAPIConfigBuilder
      def initialize
        @config = {}
      end

      def title(val)
        @config[:title] = val
      end

      def version(val)
        @config[:version] = val
      end

      def description(val)
        @config[:description] = val
      end

      def to_h
        @config
      end
    end
```

**IMPORTANT:** The `/openapi.json` and `/docs` handler blocks return Rack triples. The existing handle_request already has Rack triple passthrough (from Phase 4). So these routes work automatically.

However, the handler blocks use `-> (_)` lambdas, not `instance_exec`. The current handle_request tries to call `block.parameters` and uses `instance_exec`. The lambda `-> (_)` has one positional parameter. It gets called with `instance_exec(request, &block)` which sets self to the App and passes request as arg. The lambda ignores the request. This should work.

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/whoosh/app_openapi_spec.rb`

- [ ] **Step 5: Run full suite**

Run: `bundle exec rspec`

- [ ] **Step 6: Commit**

```bash
git add lib/whoosh/app.rb spec/whoosh/app_openapi_spec.rb
git commit -m "feat: add OpenAPI auto-generation and Swagger UI at /docs"
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
require 'rack/test'
include Rack::Test::Methods

app_instance = Whoosh::App.new

app_instance.openapi do
  title 'Smoke Test API'
  version '1.0.0'
end

app_instance.get '/health' do
  { status: 'ok' }
end

app_instance.post '/users' do |req|
  { created: true }
end

define_method(:app) { app_instance.to_rack }

get '/openapi.json'
puts \"OpenAPI: #{last_response.status}\"
spec = JSON.parse(last_response.body)
puts \"Title: #{spec['info']['title']}\"
puts \"Paths: #{spec['paths'].keys.join(', ')}\"

get '/docs'
puts \"Docs: #{last_response.status} #{last_response.content_type}\"

puts 'Phase 7 OpenAPI working!'
" 2>/dev/null
```

---

## Phase 7 Completion Checklist

- [ ] `bundle exec rspec` — all green
- [ ] SchemaConverter maps Whoosh::Schema fields to OpenAPI 3.1 schema objects
- [ ] Generator builds complete OpenAPI 3.1 spec from routes
- [ ] Path params converted to `{param}` format
- [ ] Request schemas included in spec
- [ ] Swagger UI served at `/docs`
- [ ] `/openapi.json` returns machine-readable spec
- [ ] `openapi` DSL for title/version/description
- [ ] All Phase 1-6 tests still pass

## Next Phase

After Phase 7, proceed to **Phase 8: CLI**.
