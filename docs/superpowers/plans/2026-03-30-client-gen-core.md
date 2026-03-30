# Client Generator Core Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the introspection engine, CLI command, and fallback backend scaffolding for `whoosh generate client`.

**Architecture:** OpenAPI spec is parsed into an Intermediate Representation (IR) that all client generators consume. The CLI command provides interactive selection. When no backend exists, standard auth + tasks endpoints are scaffolded.

**Tech Stack:** Ruby, Thor (existing CLI), Whoosh OpenAPI generator, Whoosh Schema DSL

---

## File Structure

```
lib/whoosh/
├── client_gen/
│   ├── introspector.rb          # Boots app, extracts OpenAPI → IR
│   ├── ir.rb                    # IR data structures
│   ├── base_generator.rb        # Shared generator logic (write files, type mapping)
│   ├── fallback_backend.rb      # Scaffolds auth + tasks backend
│   └── dependency_checker.rb    # Checks platform dependencies (node, flutter, etc.)
├── cli/
│   └── client_generator.rb      # Thor subcommand for `whoosh generate client`
│   └── main.rb                  # (modify) Register client subcommand under generate
spec/whoosh/
├── client_gen/
│   ├── introspector_spec.rb
│   ├── ir_spec.rb
│   ├── base_generator_spec.rb
│   ├── fallback_backend_spec.rb
│   └── dependency_checker_spec.rb
├── cli/
│   └── client_generator_spec.rb
```

---

### Task 1: IR Data Structures

**Files:**
- Create: `lib/whoosh/client_gen/ir.rb`
- Test: `spec/whoosh/client_gen/ir_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/ir_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh/client_gen/ir"

RSpec.describe Whoosh::ClientGen::IR do
  describe Whoosh::ClientGen::IR::Schema do
    it "builds from fields hash" do
      schema = Whoosh::ClientGen::IR::Schema.new(
        name: :task,
        fields: [
          { name: :title, type: :string, required: true },
          { name: :status, type: :string, required: false, enum: %w[pending done], default: "pending" }
        ]
      )
      expect(schema.name).to eq(:task)
      expect(schema.fields.length).to eq(2)
      expect(schema.fields.first[:required]).to be true
      expect(schema.fields.last[:enum]).to eq(%w[pending done])
    end
  end

  describe Whoosh::ClientGen::IR::Endpoint do
    it "stores method, path, action, and schemas" do
      ep = Whoosh::ClientGen::IR::Endpoint.new(
        method: :get, path: "/tasks", action: :index,
        request_schema: nil, response_schema: :task, pagination: true
      )
      expect(ep.method).to eq(:get)
      expect(ep.action).to eq(:index)
      expect(ep.pagination).to be true
    end
  end

  describe Whoosh::ClientGen::IR::Resource do
    it "groups endpoints under a resource name" do
      resource = Whoosh::ClientGen::IR::Resource.new(
        name: :tasks,
        endpoints: [
          Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index),
          Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create)
        ],
        fields: [{ name: :title, type: :string, required: true }]
      )
      expect(resource.name).to eq(:tasks)
      expect(resource.endpoints.length).to eq(2)
      expect(resource.crud_actions).to include(:index, :create)
    end
  end

  describe Whoosh::ClientGen::IR::Auth do
    it "stores auth type and endpoints" do
      auth = Whoosh::ClientGen::IR::Auth.new(
        type: :jwt,
        endpoints: {
          login: { method: :post, path: "/auth/login" },
          register: { method: :post, path: "/auth/register" },
          refresh: { method: :post, path: "/auth/refresh" },
          logout: { method: :delete, path: "/auth/logout" }
        },
        oauth_providers: []
      )
      expect(auth.type).to eq(:jwt)
      expect(auth.endpoints.keys).to include(:login, :register)
      expect(auth.oauth_providers).to be_empty
    end
  end

  describe Whoosh::ClientGen::IR::AppSpec do
    it "holds complete app IR" do
      app_spec = Whoosh::ClientGen::IR::AppSpec.new(
        auth: Whoosh::ClientGen::IR::Auth.new(type: :jwt, endpoints: {}, oauth_providers: []),
        resources: [],
        streaming: [],
        base_url: "http://localhost:9292"
      )
      expect(app_spec.base_url).to eq("http://localhost:9292")
      expect(app_spec.auth.type).to eq(:jwt)
      expect(app_spec.resources).to be_empty
    end

    it "reports whether it has resources" do
      app_spec = Whoosh::ClientGen::IR::AppSpec.new(
        auth: nil, resources: [], streaming: [], base_url: "http://localhost:9292"
      )
      expect(app_spec.has_resources?).to be false
      expect(app_spec.has_auth?).to be false
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/ir_spec.rb -v`
Expected: FAIL with "cannot load such file -- whoosh/client_gen/ir"

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/whoosh/client_gen/ir.rb
# frozen_string_literal: true

module Whoosh
  module ClientGen
    module IR
      Endpoint = Struct.new(:method, :path, :action, :request_schema, :response_schema, :pagination, keyword_init: true) do
        def initialize(method:, path:, action:, request_schema: nil, response_schema: nil, pagination: false)
          super
        end
      end

      Schema = Struct.new(:name, :fields, keyword_init: true)

      Resource = Struct.new(:name, :endpoints, :fields, keyword_init: true) do
        def crud_actions
          endpoints.map(&:action)
        end
      end

      Auth = Struct.new(:type, :endpoints, :oauth_providers, keyword_init: true) do
        def initialize(type:, endpoints:, oauth_providers: [])
          super
        end
      end

      AppSpec = Struct.new(:auth, :resources, :streaming, :base_url, keyword_init: true) do
        def has_resources?
          resources && !resources.empty?
        end

        def has_auth?
          !auth.nil?
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/ir_spec.rb -v`
Expected: All 5 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/ir.rb spec/whoosh/client_gen/ir_spec.rb
git commit -m "feat: add IR data structures for client generator"
```

---

### Task 2: OpenAPI → IR Introspector

**Files:**
- Create: `lib/whoosh/client_gen/introspector.rb`
- Test: `spec/whoosh/client_gen/introspector_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/introspector_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh"
require "whoosh/client_gen/introspector"

RSpec.describe Whoosh::ClientGen::Introspector do
  def build_test_app
    app = Whoosh::App.new
    app.auth { jwt secret: "test-secret", algorithm: :hs256, expiry: 3600 }

    app.post "/auth/login" do |req|
      { token: "fake" }
    end

    app.post "/auth/register" do |req|
      { token: "fake" }
    end

    app.get "/tasks", auth: :jwt do |req|
      { items: [] }
    end

    app.get "/tasks/:id", auth: :jwt do |req|
      { id: req.params[:id] }
    end

    app.post "/tasks", auth: :jwt do |req|
      { id: 1 }
    end

    app.put "/tasks/:id", auth: :jwt do |req|
      { updated: true }
    end

    app.delete "/tasks/:id", auth: :jwt do |req|
      { deleted: true }
    end

    app
  end

  describe "#introspect" do
    it "returns an AppSpec IR from a Whoosh app" do
      app = build_test_app
      introspector = described_class.new(app)
      ir = introspector.introspect

      expect(ir).to be_a(Whoosh::ClientGen::IR::AppSpec)
      expect(ir.base_url).to eq("http://localhost:9292")
    end

    it "detects JWT auth and auth endpoints" do
      app = build_test_app
      ir = described_class.new(app).introspect

      expect(ir.auth).not_to be_nil
      expect(ir.auth.type).to eq(:jwt)
      expect(ir.auth.endpoints).to have_key(:login)
      expect(ir.auth.endpoints).to have_key(:register)
    end

    it "groups CRUD routes into resources" do
      app = build_test_app
      ir = described_class.new(app).introspect

      expect(ir.resources.length).to eq(1)
      tasks = ir.resources.first
      expect(tasks.name).to eq(:tasks)
      expect(tasks.crud_actions).to include(:index, :show, :create, :update, :destroy)
    end
  end

  describe "#introspect with schemas" do
    it "extracts field types from request schemas" do
      app = Whoosh::App.new

      task_schema = Class.new(Whoosh::Schema) do
        field :title, String, required: true, desc: "Task title"
        field :status, String, required: false, desc: "Status"
      end

      app.post "/tasks", request: task_schema do |req|
        { id: 1 }
      end

      ir = described_class.new(app).introspect
      resource = ir.resources.first
      expect(resource.fields.length).to eq(2)
      expect(resource.fields.first[:name]).to eq(:title)
      expect(resource.fields.first[:type]).to eq(:string)
      expect(resource.fields.first[:required]).to be true
    end
  end

  describe "#introspect with no routes" do
    it "returns empty IR" do
      app = Whoosh::App.new
      ir = described_class.new(app).introspect

      expect(ir.has_auth?).to be false
      expect(ir.has_resources?).to be false
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/introspector_spec.rb -v`
Expected: FAIL with "cannot load such file -- whoosh/client_gen/introspector"

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/whoosh/client_gen/introspector.rb
# frozen_string_literal: true

require "whoosh/client_gen/ir"
require "whoosh/openapi/generator"
require "whoosh/openapi/schema_converter"

module Whoosh
  module ClientGen
    class Introspector
      AUTH_PATH_PREFIX = "/auth/"
      INTERNAL_PATHS = %w[/openapi.json /docs /redoc /metrics /healthz].freeze

      ACTION_MAP = {
        "GET" => ->(path) { path.include?("/:") || path.include?("/{") ? :show : :index },
        "POST" => ->(_path) { :create },
        "PUT" => ->(_path) { :update },
        "PATCH" => ->(_path) { :update },
        "DELETE" => ->(_path) { :destroy }
      }.freeze

      AUTH_ENDPOINT_MAP = {
        "login" => :login,
        "register" => :register,
        "signup" => :register,
        "refresh" => :refresh,
        "logout" => :logout,
        "me" => :me
      }.freeze

      def initialize(app, base_url: "http://localhost:9292")
        @app = app
        @base_url = base_url
      end

      def introspect
        routes = @app.router.routes
        auth_routes, resource_routes = partition_routes(routes)

        auth = detect_auth(auth_routes)
        resources = group_resources(resource_routes)
        streaming = detect_streaming(resource_routes)

        IR::AppSpec.new(
          auth: auth,
          resources: resources,
          streaming: streaming,
          base_url: @base_url
        )
      end

      private

      def partition_routes(routes)
        filtered = routes.reject { |r| INTERNAL_PATHS.include?(r[:path]) }
        filtered.partition { |r| r[:path].start_with?(AUTH_PATH_PREFIX) }
      end

      def detect_auth(auth_routes)
        return nil if auth_routes.empty?

        auth_type = detect_auth_type
        endpoints = {}

        auth_routes.each do |route|
          segment = route[:path].sub(AUTH_PATH_PREFIX, "").split("/").first
          key = AUTH_ENDPOINT_MAP[segment]
          next unless key
          endpoints[key] = { method: route[:method].downcase.to_sym, path: route[:path] }
        end

        oauth_providers = detect_oauth_providers(auth_routes)

        IR::Auth.new(type: auth_type, endpoints: endpoints, oauth_providers: oauth_providers)
      end

      def detect_auth_type
        if @app.instance_variable_get(:@authenticator)
          authenticator = @app.instance_variable_get(:@authenticator)
          case authenticator
          when Hash
            return :jwt if authenticator[:jwt]
            return :api_key if authenticator[:api_key]
            return :oauth2 if authenticator[:oauth2]
          else
            class_name = authenticator.class.name.to_s.downcase
            return :jwt if class_name.include?("jwt")
            return :api_key if class_name.include?("apikey") || class_name.include?("api_key")
            return :oauth2 if class_name.include?("oauth")
          end
        end
        :jwt # default assumption
      end

      def detect_oauth_providers(auth_routes)
        providers = []
        auth_routes.each do |route|
          path = route[:path]
          %i[google github apple].each do |provider|
            providers << provider if path.include?(provider.to_s)
          end
        end
        providers.uniq
      end

      def group_resources(routes)
        grouped = {}

        routes.each do |route|
          resource_name = extract_resource_name(route[:path])
          next unless resource_name

          grouped[resource_name] ||= { endpoints: [], schemas: {} }
          action = ACTION_MAP[route[:method]]&.call(route[:path]) || :custom

          match = @app.router.match(route[:method], route[:path])
          handler = match[:handler] if match

          endpoint = IR::Endpoint.new(
            method: route[:method].downcase.to_sym,
            path: route[:path],
            action: action,
            request_schema: handler&.dig(:request_schema)&.name&.to_sym,
            response_schema: handler&.dig(:response_schema)&.name&.to_sym
          )
          grouped[resource_name][:endpoints] << endpoint

          if handler&.dig(:request_schema)
            extract_fields(handler[:request_schema], grouped[resource_name][:schemas])
          end
          if handler&.dig(:response_schema)
            extract_fields(handler[:response_schema], grouped[resource_name][:schemas])
          end
        end

        grouped.map do |name, data|
          IR::Resource.new(
            name: name.to_sym,
            endpoints: data[:endpoints],
            fields: data[:schemas].values
          )
        end
      end

      def extract_resource_name(path)
        segments = path.split("/").reject(&:empty?)
        return nil if segments.empty?
        # First non-param segment is the resource name
        segments.find { |s| !s.start_with?(":") }
      end

      def extract_fields(schema_class, fields_hash)
        return unless schema_class.respond_to?(:fields)

        schema_class.fields.each do |name, opts|
          type = opts[:type]
          openapi_type = OpenAPI::SchemaConverter.type_for(type)

          fields_hash[name] = {
            name: name,
            type: openapi_type.to_sym,
            required: opts[:required] || false,
            desc: opts[:desc],
            enum: opts[:enum],
            default: opts[:default],
            min: opts[:min],
            max: opts[:max]
          }.compact
        end
      end

      def detect_streaming(routes)
        # Look for routes with SSE or WebSocket metadata
        routes.select { |r| r.dig(:metadata, :stream) || r.dig(:metadata, :sse) }
              .map { |r| { path: r[:path], type: :sse } }
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/introspector_spec.rb -v`
Expected: All 5 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/introspector.rb spec/whoosh/client_gen/introspector_spec.rb
git commit -m "feat: add OpenAPI introspector for client generator"
```

---

### Task 3: Base Generator

**Files:**
- Create: `lib/whoosh/client_gen/base_generator.rb`
- Test: `spec/whoosh/client_gen/base_generator_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/base_generator_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/base_generator"
require "whoosh/client_gen/ir"

RSpec.describe Whoosh::ClientGen::BaseGenerator do
  let(:ir) do
    Whoosh::ClientGen::IR::AppSpec.new(
      auth: Whoosh::ClientGen::IR::Auth.new(type: :jwt, endpoints: {
        login: { method: :post, path: "/auth/login" },
        register: { method: :post, path: "/auth/register" }
      }),
      resources: [
        Whoosh::ClientGen::IR::Resource.new(
          name: :tasks,
          endpoints: [
            Whoosh::ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index),
            Whoosh::ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create)
          ],
          fields: [
            { name: :title, type: :string, required: true },
            { name: :status, type: :string, required: false, enum: %w[pending done] }
          ]
        )
      ],
      streaming: [],
      base_url: "http://localhost:9292"
    )
  end

  describe "#type_for" do
    it "maps IR types to TypeScript types" do
      gen = described_class.new(ir: ir, output_dir: "/tmp/test", platform: :typescript)
      expect(gen.type_for(:string)).to eq("string")
      expect(gen.type_for(:integer)).to eq("number")
      expect(gen.type_for(:boolean)).to eq("boolean")
    end

    it "maps IR types to Swift types" do
      gen = described_class.new(ir: ir, output_dir: "/tmp/test", platform: :swift)
      expect(gen.type_for(:string)).to eq("String")
      expect(gen.type_for(:integer)).to eq("Int")
      expect(gen.type_for(:boolean)).to eq("Bool")
    end

    it "maps IR types to Dart types" do
      gen = described_class.new(ir: ir, output_dir: "/tmp/test", platform: :dart)
      expect(gen.type_for(:string)).to eq("String")
      expect(gen.type_for(:integer)).to eq("int")
      expect(gen.type_for(:boolean)).to eq("bool")
    end
  end

  describe "#write_file" do
    it "creates files with directories" do
      Dir.mktmpdir do |dir|
        gen = described_class.new(ir: ir, output_dir: dir, platform: :typescript)
        gen.write_file("src/api/client.ts", "export const API_URL = 'test';")

        path = File.join(dir, "src/api/client.ts")
        expect(File.exist?(path)).to be true
        expect(File.read(path)).to eq("export const API_URL = 'test';")
      end
    end
  end

  describe "#classify" do
    it "converts resource names to class names" do
      gen = described_class.new(ir: ir, output_dir: "/tmp/test", platform: :typescript)
      expect(gen.classify(:tasks)).to eq("Task")
      expect(gen.classify(:user_profiles)).to eq("UserProfile")
    end
  end

  describe "#singularize" do
    it "removes trailing s" do
      gen = described_class.new(ir: ir, output_dir: "/tmp/test", platform: :typescript)
      expect(gen.singularize("tasks")).to eq("task")
      expect(gen.singularize("statuses")).to eq("status")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/base_generator_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/whoosh/client_gen/base_generator.rb
# frozen_string_literal: true

require "fileutils"
require "whoosh/client_gen/ir"

module Whoosh
  module ClientGen
    class BaseGenerator
      TYPE_MAPS = {
        typescript: {
          string: "string", integer: "number", number: "number",
          boolean: "boolean", array: "any[]", object: "Record<string, any>"
        },
        swift: {
          string: "String", integer: "Int", number: "Double",
          boolean: "Bool", array: "[Any]", object: "[String: Any]"
        },
        dart: {
          string: "String", integer: "int", number: "double",
          boolean: "bool", array: "List<dynamic>", object: "Map<String, dynamic>"
        },
        ruby: {
          string: "String", integer: "Integer", number: "Float",
          boolean: "Boolean", array: "Array", object: "Hash"
        },
        html: {
          string: "text", integer: "number", number: "number",
          boolean: "checkbox", array: "text", object: "text"
        }
      }.freeze

      attr_reader :ir, :output_dir, :platform

      def initialize(ir:, output_dir:, platform:)
        @ir = ir
        @output_dir = output_dir
        @platform = platform
      end

      def generate
        raise NotImplementedError, "Subclasses must implement #generate"
      end

      def type_for(ir_type)
        TYPE_MAPS.dig(@platform, ir_type.to_sym) || "string"
      end

      def write_file(relative_path, content)
        full_path = File.join(@output_dir, relative_path)
        FileUtils.mkdir_p(File.dirname(full_path))
        File.write(full_path, content)
      end

      def classify(name)
        singular = singularize(name.to_s)
        singular.split(/[-_]/).map(&:capitalize).join
      end

      def singularize(word)
        w = word.to_s
        if w.end_with?("ies")
          w[0..-4] + "y"
        elsif w.end_with?("ses") || w.end_with?("xes") || w.end_with?("zes") || w.end_with?("ches") || w.end_with?("shes")
          w[0..-3]
        elsif w.end_with?("sses")
          w[0..-3]
        elsif w.end_with?("s") && !w.end_with?("ss") && !w.end_with?("us")
          w[0..-2]
        else
          w
        end
      end

      def camelize(name)
        name.to_s.split(/[-_]/).map(&:capitalize).join
      end

      def snake_case(name)
        name.to_s.gsub(/([A-Z])/, '_\1').downcase.sub(/^_/, "")
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/base_generator_spec.rb -v`
Expected: All 5 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/base_generator.rb spec/whoosh/client_gen/base_generator_spec.rb
git commit -m "feat: add base generator with type mapping and file helpers"
```

---

### Task 4: Dependency Checker

**Files:**
- Create: `lib/whoosh/client_gen/dependency_checker.rb`
- Test: `spec/whoosh/client_gen/dependency_checker_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/dependency_checker_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh/client_gen/dependency_checker"

RSpec.describe Whoosh::ClientGen::DependencyChecker do
  describe ".check" do
    it "returns success for htmx (no dependencies)" do
      result = described_class.check(:htmx)
      expect(result[:ok]).to be true
    end

    it "returns required dependencies for react_spa" do
      result = described_class.check(:react_spa)
      expect(result[:dependencies]).to include("node")
    end

    it "returns required dependencies for ios" do
      result = described_class.check(:ios)
      expect(result[:dependencies]).to include("xcodebuild")
    end

    it "returns required dependencies for flutter" do
      result = described_class.check(:flutter)
      expect(result[:dependencies]).to include("flutter")
    end

    it "returns required dependencies for telegram_bot" do
      result = described_class.check(:telegram_bot)
      expect(result[:dependencies]).to include("ruby")
    end
  end

  describe ".dependency_for" do
    it "returns the check command for each client type" do
      expect(described_class.dependency_for(:react_spa)).to eq([{ cmd: "node", check: "node --version", min_version: "18" }])
      expect(described_class.dependency_for(:expo)).to include(hash_including(cmd: "node"))
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/dependency_checker_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/whoosh/client_gen/dependency_checker.rb
# frozen_string_literal: true

module Whoosh
  module ClientGen
    class DependencyChecker
      DEPENDENCIES = {
        react_spa: [{ cmd: "node", check: "node --version", min_version: "18" }],
        expo: [
          { cmd: "node", check: "node --version", min_version: "18" },
          { cmd: "npx", check: "npx expo --version", min_version: nil }
        ],
        ios: [{ cmd: "xcodebuild", check: "xcodebuild -version", min_version: "15" }],
        flutter: [{ cmd: "flutter", check: "flutter --version", min_version: "3" }],
        htmx: [],
        telegram_bot: [{ cmd: "ruby", check: "ruby --version", min_version: "3.2" }],
        telegram_mini_app: [{ cmd: "node", check: "node --version", min_version: "18" }]
      }.freeze

      def self.check(client_type)
        deps = DEPENDENCIES[client_type.to_sym] || []
        return { ok: true, dependencies: [], missing: [] } if deps.empty?

        missing = []
        deps.each do |dep|
          output = `#{dep[:check]} 2>/dev/null`.strip
          if output.empty?
            missing << dep
          elsif dep[:min_version]
            version = output.scan(/(\d+)\./)[0]&.first
            if version && version.to_i < dep[:min_version].to_i
              missing << dep.merge(found_version: version)
            end
          end
        end

        {
          ok: missing.empty?,
          dependencies: deps.map { |d| d[:cmd] },
          missing: missing
        }
      end

      def self.dependency_for(client_type)
        DEPENDENCIES[client_type.to_sym] || []
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/dependency_checker_spec.rb -v`
Expected: All 5 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/dependency_checker.rb spec/whoosh/client_gen/dependency_checker_spec.rb
git commit -m "feat: add platform dependency checker for client generator"
```

---

### Task 5: Fallback Backend Scaffolding

**Files:**
- Create: `lib/whoosh/client_gen/fallback_backend.rb`
- Test: `spec/whoosh/client_gen/fallback_backend_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/client_gen/fallback_backend_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/client_gen/fallback_backend"

RSpec.describe Whoosh::ClientGen::FallbackBackend do
  describe ".generate" do
    it "creates auth and tasks endpoints" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: false)

        expect(File.exist?(File.join(dir, "endpoints", "auth_endpoint.rb"))).to be true
        expect(File.exist?(File.join(dir, "endpoints", "tasks_endpoint.rb"))).to be true
      end
    end

    it "creates auth and task schemas" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: false)

        expect(File.exist?(File.join(dir, "schemas", "auth_schemas.rb"))).to be true
        expect(File.exist?(File.join(dir, "schemas", "task_schemas.rb"))).to be true
      end
    end

    it "creates database migrations" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: false)

        migrations = Dir.glob(File.join(dir, "db", "migrations", "*.rb"))
        expect(migrations.length).to eq(2)
        names = migrations.map { |f| File.basename(f) }
        expect(names.any? { |n| n.include?("create_users") }).to be true
        expect(names.any? { |n| n.include?("create_tasks") }).to be true
      end
    end

    it "auth endpoint includes bcrypt password hashing" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: false)

        content = File.read(File.join(dir, "endpoints", "auth_endpoint.rb"))
        expect(content).to include("BCrypt::Password")
        expect(content).to include("/auth/login")
        expect(content).to include("/auth/register")
        expect(content).to include("/auth/refresh")
        expect(content).to include("/auth/logout")
        expect(content).to include("/auth/me")
      end
    end

    it "tasks endpoint has full CRUD" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: false)

        content = File.read(File.join(dir, "endpoints", "tasks_endpoint.rb"))
        expect(content).to include('get "/tasks"')
        expect(content).to include('get "/tasks/:id"')
        expect(content).to include('post "/tasks"')
        expect(content).to include('put "/tasks/:id"')
        expect(content).to include('delete "/tasks/:id"')
      end
    end

    it "includes oauth endpoints when oauth: true" do
      Dir.mktmpdir do |dir|
        described_class.generate(root: dir, oauth: true)

        content = File.read(File.join(dir, "endpoints", "auth_endpoint.rb"))
        expect(content).to include("/auth/:provider")
        expect(content).to include("/auth/:provider/callback")
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/client_gen/fallback_backend_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write minimal implementation**

```ruby
# lib/whoosh/client_gen/fallback_backend.rb
# frozen_string_literal: true

require "fileutils"

module Whoosh
  module ClientGen
    class FallbackBackend
      def self.generate(root: Dir.pwd, oauth: false)
        new(root: root, oauth: oauth).generate
      end

      def initialize(root:, oauth:)
        @root = root
        @oauth = oauth
      end

      def generate
        generate_schemas
        generate_auth_endpoint
        generate_tasks_endpoint
        generate_migrations
      end

      private

      def generate_schemas
        FileUtils.mkdir_p(File.join(@root, "schemas"))

        File.write(File.join(@root, "schemas", "auth_schemas.rb"), <<~RUBY)
          # frozen_string_literal: true

          class LoginRequest < Whoosh::Schema
            field :email, String, required: true, desc: "User email"
            field :password, String, required: true, desc: "Password"
          end

          class RegisterRequest < Whoosh::Schema
            field :name, String, required: true, desc: "Full name"
            field :email, String, required: true, desc: "User email"
            field :password, String, required: true, min_length: 8, desc: "Password (min 8 chars)"
          end

          class TokenResponse < Whoosh::Schema
            field :token, String, required: true, desc: "JWT access token"
            field :refresh_token, String, required: true, desc: "Refresh token"
          end

          class UserResponse < Whoosh::Schema
            field :id, Integer, required: true, desc: "User ID"
            field :name, String, required: true, desc: "Full name"
            field :email, String, required: true, desc: "User email"
          end
        RUBY

        File.write(File.join(@root, "schemas", "task_schemas.rb"), <<~RUBY)
          # frozen_string_literal: true

          class CreateTaskRequest < Whoosh::Schema
            field :title, String, required: true, min_length: 1, max_length: 255, desc: "Task title"
            field :description, String, desc: "Task description"
            field :status, String, enum: %w[pending in_progress done], default: "pending", desc: "Task status"
            field :due_date, String, desc: "Due date (ISO 8601)"
          end

          class UpdateTaskRequest < Whoosh::Schema
            field :title, String, max_length: 255, desc: "Task title"
            field :description, String, desc: "Task description"
            field :status, String, enum: %w[pending in_progress done], desc: "Task status"
            field :due_date, String, desc: "Due date (ISO 8601)"
          end

          class TaskResponse < Whoosh::Schema
            field :id, Integer, required: true, desc: "Task ID"
            field :title, String, required: true, desc: "Task title"
            field :description, String, desc: "Task description"
            field :status, String, required: true, desc: "Task status"
            field :due_date, String, desc: "Due date"
            field :created_at, String, desc: "Created timestamp"
            field :updated_at, String, desc: "Updated timestamp"
          end
        RUBY
      end

      def generate_auth_endpoint
        FileUtils.mkdir_p(File.join(@root, "endpoints"))

        oauth_routes = if @oauth
          <<~RUBY

            get "/auth/:provider" do |req|
              provider = req.params[:provider].to_sym
              url = App.oauth2_authorize_url(provider: provider)
              Response.redirect(url)
            end

            get "/auth/:provider/callback" do |req|
              provider = req.params[:provider].to_sym
              user_info = App.oauth2_callback(provider: provider, code: req.query_params["code"])

              user = db[:users].where(email: user_info[:email]).first
              unless user
                user_id = db[:users].insert(
                  name: user_info[:name], email: user_info[:email],
                  password_hash: "oauth2", created_at: Time.now
                )
                user = db[:users].where(id: user_id).first
              end

              token = App.jwt.generate(sub: user[:id], email: user[:email])
              refresh = SecureRandom.hex(32)
              { token: token, refresh_token: refresh }
            end
          RUBY
        else
          ""
        end

        File.write(File.join(@root, "endpoints", "auth_endpoint.rb"), <<~RUBY)
          # frozen_string_literal: true

          require "bcrypt"
          require "securerandom"

          App.post "/auth/register", request: RegisterRequest, response: TokenResponse do |req, db:|
            existing = db[:users].where(email: req.body[:email]).first
            raise Whoosh::Errors::ValidationError, "Email already registered" if existing

            password_hash = BCrypt::Password.create(req.body[:password])
            user_id = db[:users].insert(
              name: req.body[:name], email: req.body[:email],
              password_hash: password_hash.to_s, created_at: Time.now
            )

            token = App.jwt.generate(sub: user_id, email: req.body[:email])
            refresh = SecureRandom.hex(32)
            { token: token, refresh_token: refresh }
          end

          App.post "/auth/login", request: LoginRequest, response: TokenResponse do |req, db:|
            user = db[:users].where(email: req.body[:email]).first
            raise Whoosh::Errors::UnauthorizedError, "Invalid credentials" unless user

            unless BCrypt::Password.new(user[:password_hash]) == req.body[:password]
              raise Whoosh::Errors::UnauthorizedError, "Invalid credentials"
            end

            token = App.jwt.generate(sub: user[:id], email: user[:email])
            refresh = SecureRandom.hex(32)
            { token: token, refresh_token: refresh }
          end

          App.post "/auth/refresh", auth: :jwt do |req|
            claims = req.env["whoosh.auth"]
            token = App.jwt.generate(sub: claims[:sub], email: claims[:email])
            refresh = SecureRandom.hex(32)
            { token: token, refresh_token: refresh }
          end

          App.delete "/auth/logout", auth: :jwt do |req|
            { message: "Logged out" }
          end

          App.get "/auth/me", auth: :jwt, response: UserResponse do |req, db:|
            claims = req.env["whoosh.auth"]
            user = db[:users].where(id: claims[:sub]).first
            raise Whoosh::Errors::NotFoundError, "User not found" unless user
            { id: user[:id], name: user[:name], email: user[:email] }
          end
          #{oauth_routes}
        RUBY
      end

      def generate_tasks_endpoint
        File.write(File.join(@root, "endpoints", "tasks_endpoint.rb"), <<~RUBY)
          # frozen_string_literal: true

          App.get "/tasks", auth: :jwt do |req, db:|
            paginate_cursor(db[:tasks].where(user_id: req.env["whoosh.auth"][:sub]).order(:id),
              cursor: req.query_params["cursor"], limit: (req.query_params["limit"] || 20).to_i)
          end

          App.get "/tasks/:id", auth: :jwt, response: TaskResponse do |req, db:|
            task = db[:tasks].where(id: req.params[:id], user_id: req.env["whoosh.auth"][:sub]).first
            raise Whoosh::Errors::NotFoundError, "Task not found" unless task
            task
          end

          App.post "/tasks", auth: :jwt, request: CreateTaskRequest, response: TaskResponse do |req, db:|
            task_id = db[:tasks].insert(
              title: req.body[:title],
              description: req.body[:description],
              status: req.body[:status] || "pending",
              due_date: req.body[:due_date],
              user_id: req.env["whoosh.auth"][:sub],
              created_at: Time.now
            )
            db[:tasks].where(id: task_id).first
          end

          App.put "/tasks/:id", auth: :jwt, request: UpdateTaskRequest, response: TaskResponse do |req, db:|
            task = db[:tasks].where(id: req.params[:id], user_id: req.env["whoosh.auth"][:sub])
            raise Whoosh::Errors::NotFoundError, "Task not found" unless task.first

            updates = {}
            updates[:title] = req.body[:title] if req.body[:title]
            updates[:description] = req.body[:description] if req.body[:description]
            updates[:status] = req.body[:status] if req.body[:status]
            updates[:due_date] = req.body[:due_date] if req.body[:due_date]
            updates[:updated_at] = Time.now

            task.update(updates)
            task.first
          end

          App.delete "/tasks/:id", auth: :jwt do |req, db:|
            count = db[:tasks].where(id: req.params[:id], user_id: req.env["whoosh.auth"][:sub]).delete
            raise Whoosh::Errors::NotFoundError, "Task not found" if count.zero?
            { deleted: true }
          end
        RUBY
      end

      def generate_migrations
        FileUtils.mkdir_p(File.join(@root, "db", "migrations"))
        ts = Time.now.strftime("%Y%m%d%H%M%S")

        File.write(File.join(@root, "db", "migrations", "#{ts}_create_users.rb"), <<~RUBY)
          Sequel.migration do
            change do
              create_table(:users) do
                primary_key :id
                String :name, null: false
                String :email, null: false
                String :password_hash, null: false
                DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
                DateTime :updated_at

                unique :email
                index :email
              end
            end
          end
        RUBY

        ts2 = (Time.now + 1).strftime("%Y%m%d%H%M%S")
        File.write(File.join(@root, "db", "migrations", "#{ts2}_create_tasks.rb"), <<~RUBY)
          Sequel.migration do
            change do
              create_table(:tasks) do
                primary_key :id
                foreign_key :user_id, :users, null: false
                String :title, null: false
                String :description, text: true
                String :status, null: false, default: "pending"
                Date :due_date
                DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
                DateTime :updated_at

                index :user_id
                index [:user_id, :status]
              end
            end
          end
        RUBY
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/fallback_backend_spec.rb -v`
Expected: All 6 examples pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/client_gen/fallback_backend.rb spec/whoosh/client_gen/fallback_backend_spec.rb
git commit -m "feat: add fallback backend scaffolding (auth + tasks CRUD)"
```

---

### Task 6: CLI Command — `whoosh generate client`

**Files:**
- Create: `lib/whoosh/cli/client_generator.rb`
- Modify: `lib/whoosh/cli/main.rb:564-603`
- Test: `spec/whoosh/cli/client_generator_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/cli/client_generator_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh/cli/client_generator"

RSpec.describe Whoosh::CLI::ClientGenerator do
  describe ".client_types" do
    it "lists all supported client types" do
      types = described_class.client_types
      expect(types).to include(:react_spa, :expo, :ios, :flutter, :htmx, :telegram_bot, :telegram_mini_app)
    end
  end

  describe "#run" do
    it "rejects unknown client types" do
      expect {
        described_class.new(type: "android", oauth: false, dir: nil).validate!
      }.to raise_error(Whoosh::ClientGen::Error, /Unknown client type/)
    end

    it "accepts valid client types" do
      %w[react_spa expo ios flutter htmx telegram_bot telegram_mini_app].each do |type|
        generator = described_class.new(type: type, oauth: false, dir: nil)
        expect { generator.validate! }.not_to raise_error
      end
    end
  end

  describe "#default_output_dir" do
    it "returns clients/<type> by default" do
      gen = described_class.new(type: "react_spa", oauth: false, dir: nil)
      expect(gen.default_output_dir).to eq("clients/react_spa")
    end

    it "uses custom dir when provided" do
      gen = described_class.new(type: "react_spa", oauth: false, dir: "my_frontend")
      expect(gen.output_dir).to eq("my_frontend")
    end
  end

  describe "#introspect_or_fallback" do
    it "returns fallback IR when no app exists" do
      Dir.mktmpdir do |dir|
        gen = described_class.new(type: "react_spa", oauth: false, dir: nil, root: dir)
        result = gen.introspect_or_fallback
        expect(result[:mode]).to eq(:fallback)
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/cli/client_generator_spec.rb -v`
Expected: FAIL with "cannot load such file"

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/cli/client_generator.rb
# frozen_string_literal: true

require "whoosh/client_gen/ir"
require "whoosh/client_gen/introspector"
require "whoosh/client_gen/base_generator"
require "whoosh/client_gen/dependency_checker"
require "whoosh/client_gen/fallback_backend"

module Whoosh
  module ClientGen
    class Error < StandardError; end
  end

  module CLI
    class ClientGenerator
      CLIENT_TYPES = %i[react_spa expo ios flutter htmx telegram_bot telegram_mini_app].freeze

      attr_reader :type, :oauth, :output_dir

      def self.client_types
        CLIENT_TYPES
      end

      def initialize(type:, oauth:, dir:, root: Dir.pwd)
        @type = type.to_sym
        @oauth = oauth
        @output_dir = dir || default_output_dir
        @root = root
      end

      def run
        validate!
        check_dependencies!
        result = introspect_or_fallback

        case result[:mode]
        when :introspected
          display_found(result[:ir])
          ir = confirm_selection(result[:ir])
          generate_client(ir)
        when :fallback
          display_fallback_prompt
          generate_fallback_backend
          ir = build_fallback_ir
          generate_client(ir)
        end

        display_success
      end

      def validate!
        unless CLIENT_TYPES.include?(@type)
          raise ClientGen::Error, "Unknown client type: #{@type}. Supported: #{CLIENT_TYPES.join(", ")}"
        end
      end

      def default_output_dir
        "clients/#{@type}"
      end

      def check_dependencies!
        result = ClientGen::DependencyChecker.check(@type)
        return if result[:ok]

        puts "\n⚠️  Missing dependencies for #{@type}:"
        result[:missing].each do |dep|
          msg = "  - #{dep[:cmd]} (check: #{dep[:check]})"
          msg += " — found v#{dep[:found_version]}, need v#{dep[:min_version]}+" if dep[:found_version]
          puts msg
        end
        puts "\nInstall the missing dependencies and try again."
        exit 1
      end

      def introspect_or_fallback
        app = load_app
        if app
          introspector = ClientGen::Introspector.new(app, base_url: detect_base_url(app))
          ir = introspector.introspect
          if ir.has_resources? || ir.has_auth?
            { mode: :introspected, ir: ir }
          else
            { mode: :fallback }
          end
        else
          { mode: :fallback }
        end
      end

      private

      def load_app
        app_file = File.join(@root, "app.rb")
        return nil unless File.exist?(app_file)

        require app_file
        ObjectSpace.each_object(Whoosh::App).first
      rescue => e
        puts "⚠️  Failed to load app: #{e.message}"
        puts "Run `whoosh check` to debug."
        nil
      end

      def detect_base_url(app)
        config = app.instance_variable_get(:@config)
        port = config&.respond_to?(:port) ? config.port : 9292
        host = config&.respond_to?(:host) ? config.host : "localhost"
        "http://#{host}:#{port}"
      end

      def display_found(ir)
        puts "\n🔍 Inspecting Whoosh app...\n\n"
        puts "Found:"
        puts "  Auth:       #{ir.auth&.type || "none"}"
        ir.resources.each do |r|
          puts "  Resource:   #{r.name} (#{r.endpoints.length} endpoints)"
        end
        ir.streaming.each do |s|
          puts "  Streaming:  #{s[:type]} on #{s[:path]}"
        end
        puts
      end

      def confirm_selection(ir)
        # In non-interactive mode, use all resources
        # Interactive TTY selection can be added later
        ir
      end

      def display_fallback_prompt
        puts "\n⚠️  No Whoosh app found (or no routes defined).\n\n"
        puts "Generating standard starter with:"
        puts "  - JWT auth (email/password login + register)"
        puts "  - Tasks CRUD (title, description, status, due_date)"
        puts "  - Matching backend endpoints"
        if @oauth
          puts "  - OAuth2 (Google, GitHub, Apple)"
        end
        puts
      end

      def generate_fallback_backend
        ClientGen::FallbackBackend.generate(root: @root, oauth: @oauth)
        puts "✅ Backend endpoints generated"
      end

      def build_fallback_ir
        ClientGen::IR::AppSpec.new(
          auth: ClientGen::IR::Auth.new(
            type: :jwt,
            endpoints: {
              login: { method: :post, path: "/auth/login" },
              register: { method: :post, path: "/auth/register" },
              refresh: { method: :post, path: "/auth/refresh" },
              logout: { method: :delete, path: "/auth/logout" },
              me: { method: :get, path: "/auth/me" }
            },
            oauth_providers: @oauth ? %i[google github apple] : []
          ),
          resources: [
            ClientGen::IR::Resource.new(
              name: :tasks,
              endpoints: [
                ClientGen::IR::Endpoint.new(method: :get, path: "/tasks", action: :index, pagination: true),
                ClientGen::IR::Endpoint.new(method: :get, path: "/tasks/:id", action: :show),
                ClientGen::IR::Endpoint.new(method: :post, path: "/tasks", action: :create),
                ClientGen::IR::Endpoint.new(method: :put, path: "/tasks/:id", action: :update),
                ClientGen::IR::Endpoint.new(method: :delete, path: "/tasks/:id", action: :destroy)
              ],
              fields: [
                { name: :title, type: :string, required: true },
                { name: :description, type: :string, required: false },
                { name: :status, type: :string, required: false, enum: %w[pending in_progress done], default: "pending" },
                { name: :due_date, type: :string, required: false }
              ]
            )
          ],
          streaming: [],
          base_url: "http://localhost:9292"
        )
      end

      def generate_client(ir)
        generator_class = load_generator_class
        output = File.join(@root, @output_dir)

        if Dir.exist?(output) && !Dir.empty?(output)
          puts "⚠️  #{@output_dir}/ already exists."
          print "Overwrite? [y/N] "
          answer = $stdin.gets&.strip&.downcase
          unless answer == "y"
            puts "Aborted."
            exit 0
          end
          FileUtils.rm_rf(output)
        end

        generator_class.new(ir: ir, output_dir: output, platform: platform_for_type).generate
      end

      def load_generator_class
        require "whoosh/client_gen/generators/#{@type}"
        Whoosh::ClientGen::Generators.const_get(camelize(@type.to_s))
      end

      def platform_for_type
        case @type
        when :react_spa, :expo, :telegram_mini_app then :typescript
        when :ios then :swift
        when :flutter then :dart
        when :htmx then :html
        when :telegram_bot then :ruby
        end
      end

      def camelize(str)
        str.split("_").map(&:capitalize).join
      end

      def display_success
        puts "\n✅ Generated #{@type} client in #{@output_dir}/"
        case @type
        when :react_spa, :telegram_mini_app
          puts "   Run: cd #{@output_dir} && npm install && npm run dev"
        when :expo
          puts "   Run: cd #{@output_dir} && npm install && npx expo start"
        when :ios
          puts "   Run: open #{@output_dir}/WhooshApp.xcodeproj"
        when :flutter
          puts "   Run: cd #{@output_dir} && flutter pub get && flutter run"
        when :htmx
          puts "   Run: cd #{@output_dir} && open index.html (or any static server)"
        when :telegram_bot
          puts "   Run: cd #{@output_dir} && bundle install && ruby bot.rb"
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/cli/client_generator_spec.rb -v`
Expected: All 4 examples pass

- [ ] **Step 5: Register the command in main.rb**

Add inside the `subcommand "generate"` block in `lib/whoosh/cli/main.rb`, after the `proto` command (around line 602):

```ruby
        desc "client TYPE", "Generate a client app (react_spa, expo, ios, flutter, htmx, telegram_bot, telegram_mini_app)"
        option :oauth, type: :boolean, default: false, desc: "Include OAuth2 social login"
        option :dir, type: :string, desc: "Output directory (default: clients/<type>)"
        def client(type)
          require "whoosh/cli/client_generator"
          Whoosh::CLI::ClientGenerator.new(
            type: type, oauth: options[:oauth], dir: options[:dir]
          ).run
        end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/cli/client_generator_spec.rb spec/whoosh/cli/main_spec.rb -v`
Expected: All pass

- [ ] **Step 7: Commit**

```bash
git add lib/whoosh/cli/client_generator.rb lib/whoosh/cli/main.rb spec/whoosh/cli/client_generator_spec.rb
git commit -m "feat: add whoosh generate client CLI command"
```

---

### Task 7: Integration Test — Full Round-Trip

**Files:**
- Create: `spec/whoosh/client_gen/integration_spec.rb`

- [ ] **Step 1: Write the integration test**

```ruby
# spec/whoosh/client_gen/integration_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "whoosh"
require "whoosh/client_gen/introspector"
require "whoosh/client_gen/fallback_backend"

RSpec.describe "Client Generator Integration" do
  describe "full introspection round-trip" do
    it "introspects a Whoosh app with auth and CRUD routes" do
      app = Whoosh::App.new
      app.auth { jwt secret: "test-secret-key-for-testing", algorithm: :hs256, expiry: 3600 }

      task_request = Class.new(Whoosh::Schema) do
        field :title, String, required: true, desc: "Task title"
        field :description, String, desc: "Description"
        field :status, String, enum: %w[pending in_progress done], default: "pending", desc: "Status"
      end

      app.post "/auth/login" do |req|
        { token: "test" }
      end

      app.post "/auth/register" do |req|
        { token: "test" }
      end

      app.get "/tasks", auth: :jwt do |req|
        { items: [], cursor: nil }
      end

      app.get "/tasks/:id", auth: :jwt do |req|
        { id: 1, title: "Test" }
      end

      app.post "/tasks", auth: :jwt, request: task_request do |req|
        { id: 1, title: req.body[:title] }
      end

      app.put "/tasks/:id", auth: :jwt, request: task_request do |req|
        { id: 1, title: req.body[:title] }
      end

      app.delete "/tasks/:id", auth: :jwt do |req|
        { deleted: true }
      end

      introspector = Whoosh::ClientGen::Introspector.new(app)
      ir = introspector.introspect

      expect(ir.auth.type).to eq(:jwt)
      expect(ir.auth.endpoints).to have_key(:login)
      expect(ir.auth.endpoints).to have_key(:register)
      expect(ir.resources.length).to eq(1)

      tasks = ir.resources.first
      expect(tasks.name).to eq(:tasks)
      expect(tasks.crud_actions).to match_array([:index, :show, :create, :update, :destroy])
      expect(tasks.fields.length).to eq(3)
      expect(tasks.fields.find { |f| f[:name] == :title }[:type]).to eq(:string)
    end
  end

  describe "fallback backend generation" do
    it "generates a complete backend that could be introspected" do
      Dir.mktmpdir do |dir|
        Whoosh::ClientGen::FallbackBackend.generate(root: dir, oauth: false)

        # Verify all required files exist
        %w[
          endpoints/auth_endpoint.rb
          endpoints/tasks_endpoint.rb
          schemas/auth_schemas.rb
          schemas/task_schemas.rb
        ].each do |path|
          expect(File.exist?(File.join(dir, path))).to be(true), "Missing: #{path}"
        end

        migrations = Dir.glob(File.join(dir, "db/migrations/*.rb"))
        expect(migrations.length).to eq(2)
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/client_gen/integration_spec.rb -v`
Expected: All 2 examples pass

- [ ] **Step 3: Commit**

```bash
git add spec/whoosh/client_gen/integration_spec.rb
git commit -m "test: add client generator integration tests"
```
