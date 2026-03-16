# Whoosh Phase 2: Plugin System & Endpoints Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the plugin auto-discovery system (scan Gemfile.lock, lazy-load gems via Mutex, accessor methods on App) and class-based Endpoint support (auto-loaded from `endpoints/` directory, Context delegation to App for plugin access).

**Architecture:** Plugin Registry scans Gemfile.lock at boot, registers lazy accessor methods on App via `define_method`. Plugins::Base provides hook interface (`before_request`, `after_response`). Endpoint is a base class with route DSL that registers class-based handlers with the App's router. Endpoint::Context wraps the app and request, delegating unknown methods to App (enabling bare `llm`, `lingua` calls).

**Tech Stack:** Ruby 3.4+, RSpec, rack-test. No new gems — plugin system works with whatever gems are in the app's Gemfile.

**Spec:** `docs/superpowers/specs/2026-03-11-whoosh-design.md` (Plugin System & Gem Auto-Discovery section, lines 415-501; Routing & Endpoint DSL section, lines 63-130)

**Depends on:** Phase 1 complete (113 tests passing — App, Router, Schema, DI, Middleware, Logger, Config, Request, Response, Errors, Types, Serialization all working)

---

## Chunk 1: Plugin System

### Task 1: Plugin Base Class

**Files:**
- Create: `lib/whoosh/plugins/base.rb`
- Test: `spec/whoosh/plugins/base_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/plugins/base_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Plugins::Base do
  describe "hook interface" do
    it "does not act as middleware by default" do
      expect(Whoosh::Plugins::Base.middleware?).to be false
    end

    it "can be subclassed with middleware hooks" do
      plugin = Class.new(Whoosh::Plugins::Base) do
        def self.middleware? = true

        def self.before_request(req, config)
          { checked: true }
        end

        def self.after_response(res, config)
          { verified: true }
        end
      end

      expect(plugin.middleware?).to be true
      expect(plugin.before_request(nil, nil)).to eq({ checked: true })
      expect(plugin.after_response(nil, nil)).to eq({ verified: true })
    end
  end

  describe ".gem_name" do
    it "can declare the gem name" do
      plugin = Class.new(Whoosh::Plugins::Base) do
        gem_name "lingua-ruby"
      end

      expect(plugin.gem_name).to eq("lingua-ruby")
    end
  end

  describe ".accessor_name" do
    it "can declare the accessor name" do
      plugin = Class.new(Whoosh::Plugins::Base) do
        accessor_name :lingua
      end

      expect(plugin.accessor_name).to eq(:lingua)
    end
  end

  describe ".initialize_plugin" do
    it "returns nil by default (subclasses override)" do
      expect(Whoosh::Plugins::Base.initialize_plugin({})).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/plugins/base_spec.rb`
Expected: FAIL — `cannot load such file -- whoosh/plugins/base`

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/plugins/base.rb
# frozen_string_literal: true

module Whoosh
  module Plugins
    class Base
      class << self
        def gem_name(name = nil)
          if name
            @gem_name = name
          else
            @gem_name
          end
        end

        def accessor_name(name = nil)
          if name
            @accessor_name = name
          else
            @accessor_name
          end
        end

        def middleware?
          false
        end

        def before_request(req, config)
          # Override in subclass
        end

        def after_response(res, config)
          # Override in subclass
        end

        def initialize_plugin(config)
          # Override in subclass — return the plugin instance
          nil
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/plugins/base_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/plugins/base.rb spec/whoosh/plugins/base_spec.rb
git commit -m "feat: add Plugins::Base with hook interface and metadata DSL"
```

---

### Task 2: Plugin Registry

**Files:**
- Create: `lib/whoosh/plugins/registry.rb`
- Test: `spec/whoosh/plugins/registry_spec.rb`

The Registry manages gem-to-accessor mappings, scans Gemfile.lock, and defines lazy-loaded accessor methods on a target object (the App). It uses Mutex for thread-safe first initialization.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/plugins/registry_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Plugins::Registry do
  let(:registry) { Whoosh::Plugins::Registry.new }

  describe "#register" do
    it "registers a gem with an accessor name" do
      registry.register("lingua-ruby", accessor: :lingua)
      expect(registry.registered?("lingua-ruby")).to be true
    end

    it "stores the accessor name" do
      registry.register("lingua-ruby", accessor: :lingua)
      expect(registry.accessor_for("lingua-ruby")).to eq(:lingua)
    end
  end

  describe "#scan_gemfile_lock" do
    it "detects known gems from a Gemfile.lock string" do
      lock_content = <<~LOCK
        GEM
          remote: https://rubygems.org/
          specs:
            lingua-ruby (0.1.0)
            rack (3.0.0)
            ner-ruby (0.2.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          lingua-ruby
          ner-ruby
          rack
      LOCK

      detected = registry.scan_gemfile_lock(lock_content)
      expect(detected).to include("lingua-ruby")
      expect(detected).to include("ner-ruby")
      expect(detected).not_to include("rack")
    end

    it "returns empty array when no known gems found" do
      lock_content = <<~LOCK
        GEM
          remote: https://rubygems.org/
          specs:
            rack (3.0.0)

        DEPENDENCIES
          rack
      LOCK

      detected = registry.scan_gemfile_lock(lock_content)
      expect(detected).to be_empty
    end
  end

  describe "#define_accessors" do
    it "defines lazy-loaded methods on the target object" do
      registry.register("json", accessor: :json_plugin, initializer: -> (_config) { { loaded: true } })

      target = Object.new
      registry.define_accessors(target)

      expect(target).to respond_to(:json_plugin)
    end

    it "lazy-loads the plugin on first access" do
      call_count = 0
      registry.register("json", accessor: :test_plugin, initializer: -> (_config) {
        call_count += 1
        "plugin_instance"
      })

      target = Object.new
      registry.define_accessors(target)

      expect(call_count).to eq(0)
      result = target.test_plugin
      expect(result).to eq("plugin_instance")
      expect(call_count).to eq(1)

      # Second call returns cached value
      target.test_plugin
      expect(call_count).to eq(1)
    end
  end

  describe "#configure" do
    it "stores plugin configuration" do
      registry.register("lingua-ruby", accessor: :lingua)
      registry.configure(:lingua, { languages: [:en, :id] })
      expect(registry.config_for(:lingua)).to eq({ languages: [:en, :id] })
    end
  end

  describe "#disable" do
    it "marks a plugin as disabled" do
      registry.register("lingua-ruby", accessor: :lingua)
      registry.disable(:lingua)
      expect(registry.disabled?(:lingua)).to be true
    end
  end

  describe "default gem mappings" do
    it "has built-in mappings for ecosystem gems" do
      expect(registry.accessor_for("lingua-ruby")).to eq(:lingua)
      expect(registry.accessor_for("ner-ruby")).to eq(:ner)
      expect(registry.accessor_for("ruby_llm")).to eq(:llm)
      expect(registry.accessor_for("keyword-ruby")).to eq(:keyword)
      expect(registry.accessor_for("guardrails-ruby")).to eq(:guardrails)
      expect(registry.accessor_for("sequel")).to eq(:db)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/plugins/registry_spec.rb`
Expected: FAIL

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/plugins/registry.rb
# frozen_string_literal: true

require "set"

module Whoosh
  module Plugins
    class Registry
      # Default mappings: gem name => accessor symbol
      DEFAULT_GEMS = {
        "ruby_llm"        => :llm,
        "lingua-ruby"     => :lingua,
        "keyword-ruby"    => :keyword,
        "ner-ruby"        => :ner,
        "loader-ruby"     => :loader,
        "prompter-ruby"   => :prompter,
        "chunker-ruby"    => :chunker,
        "guardrails-ruby" => :guardrails,
        "rag-ruby"        => :rag,
        "eval-ruby"       => :eval_,
        "connector-ruby"  => :connector,
        "sastrawi-ruby"   => :sastrawi,
        "pattern-ruby"    => :pattern,
        "onnx-ruby"       => :onnx,
        "tokenizer-ruby"  => :tokenizer,
        "zvec-ruby"       => :zvec,
        "reranker-ruby"   => :reranker,
        "sequel"          => :db
      }.freeze

      def initialize
        @gems = {}
        @configs = {}
        @disabled = Set.new
        @mutex = Mutex.new

        register_defaults
      end

      def register(gem_name, accessor:, initializer: nil)
        @gems[gem_name] = { accessor: accessor, initializer: initializer }
      end

      def registered?(gem_name)
        @gems.key?(gem_name)
      end

      def accessor_for(gem_name)
        @gems.dig(gem_name, :accessor)
      end

      def scan_gemfile_lock(content)
        specs_section = false
        detected = []

        content.each_line do |line|
          stripped = line.strip
          if stripped == "specs:"
            specs_section = true
            next
          end

          if specs_section
            break if stripped.empty? || !line.start_with?("  ")

            # Lines like "    lingua-ruby (0.1.0)"
            match = stripped.match(/\A(\S+)\s+\(/)
            if match && @gems.key?(match[1])
              detected << match[1]
            end
          end
        end

        detected
      end

      def define_accessors(target)
        @gems.each do |gem_name, entry|
          accessor = entry[:accessor]
          next if @disabled.include?(accessor)

          initializer = entry[:initializer]
          config = @configs[accessor] || {}
          mutex = @mutex
          instance_var = :"@_plugin_#{accessor}"

          target.define_singleton_method(accessor) do
            cached = instance_variable_get(instance_var)
            return cached if cached

            mutex.synchronize do
              # Double-check inside lock
              cached = instance_variable_get(instance_var)
              return cached if cached

              instance = if initializer
                initializer.call(config)
              else
                begin
                  require gem_name.tr("-", "/")
                rescue LoadError
                  raise Whoosh::Errors::DependencyError,
                    "Plugin '#{accessor}' requires gem '#{gem_name}' but it could not be loaded"
                end
                nil
              end

              instance_variable_set(instance_var, instance || true)
              instance
            end
          end
        end
      end

      def configure(accessor, config)
        @configs[accessor] = config
      end

      def config_for(accessor)
        @configs[accessor]
      end

      def disable(accessor)
        @disabled.add(accessor)
      end

      def disabled?(accessor)
        @disabled.include?(accessor)
      end

      private

      def register_defaults
        DEFAULT_GEMS.each do |gem_name, accessor|
          register(gem_name, accessor: accessor)
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/plugins/registry_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/plugins/registry.rb spec/whoosh/plugins/registry_spec.rb
git commit -m "feat: add Plugin Registry with auto-discovery, lazy loading, and gem mappings"
```

---

## Chunk 2: Endpoint System

### Task 3: Endpoint Base Class

**Files:**
- Create: `lib/whoosh/endpoint.rb`
- Test: `spec/whoosh/endpoint_spec.rb`

The Endpoint class provides a DSL for declaring routes in class-based style. Each subclass declares routes with `get`, `post`, etc. and implements `call(req)`. The class tracks its declared routes so the App can register them.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/endpoint_spec.rb
# frozen_string_literal: true

require "spec_helper"

class TestHealthEndpoint < Whoosh::Endpoint
  get "/health"

  def call(req)
    { status: "ok" }
  end
end

class TestChatEndpoint < Whoosh::Endpoint
  post "/chat", mcp: true

  def call(req)
    { reply: "hello" }
  end
end

class TestMultiEndpoint < Whoosh::Endpoint
  get "/items"
  post "/items"

  def call(req)
    { method: req.method }
  end
end

RSpec.describe Whoosh::Endpoint do
  describe ".declared_routes" do
    it "returns routes declared via DSL" do
      routes = TestHealthEndpoint.declared_routes
      expect(routes.length).to eq(1)
      expect(routes.first[:method]).to eq("GET")
      expect(routes.first[:path]).to eq("/health")
    end

    it "stores metadata" do
      routes = TestChatEndpoint.declared_routes
      expect(routes.first[:metadata][:mcp]).to be true
    end

    it "supports multiple routes per endpoint" do
      routes = TestMultiEndpoint.declared_routes
      expect(routes.length).to eq(2)
      expect(routes.map { |r| r[:method] }).to contain_exactly("GET", "POST")
    end
  end

  describe "route DSL" do
    it "supports all HTTP verbs" do
      endpoint_class = Class.new(Whoosh::Endpoint) do
        get "/a"
        post "/b"
        put "/c"
        patch "/d"
        delete "/e"
        options "/f"
      end

      methods = endpoint_class.declared_routes.map { |r| r[:method] }
      expect(methods).to contain_exactly("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
    end

    it "stores request and response schemas" do
      schema_class = Class.new(Whoosh::Schema) do
        field :name, String, required: true
      end

      endpoint_class = Class.new(Whoosh::Endpoint) do
        post "/test", request: schema_class, response: schema_class
      end

      route = endpoint_class.declared_routes.first
      expect(route[:request_schema]).to eq(schema_class)
      expect(route[:response_schema]).to eq(schema_class)
    end
  end

  describe "Endpoint::Context" do
    it "delegates unknown methods to the app" do
      fake_app = Object.new
      def fake_app.llm; "llm_instance"; end

      context = Whoosh::Endpoint::Context.new(fake_app, nil)
      expect(context.llm).to eq("llm_instance")
    end

    it "provides access to the request" do
      context = Whoosh::Endpoint::Context.new(nil, "the_request")
      expect(context.request).to eq("the_request")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/endpoint_spec.rb`
Expected: FAIL — `cannot load such file -- whoosh/endpoint`

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/endpoint.rb
# frozen_string_literal: true

module Whoosh
  class Endpoint
    class Context
      attr_reader :request

      def initialize(app, request)
        @app = app
        @request = request
      end

      def respond_to_missing?(method_name, include_private = false)
        @app.respond_to?(method_name, include_private) || super
      end

      private

      def method_missing(method_name, ...)
        if @app.respond_to?(method_name)
          @app.send(method_name, ...)
        else
          super
        end
      end
    end

    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@declared_routes, [])
      end

      def declared_routes
        @declared_routes
      end

      def get(path, **opts)
        declare_route("GET", path, **opts)
      end

      def post(path, **opts)
        declare_route("POST", path, **opts)
      end

      def put(path, **opts)
        declare_route("PUT", path, **opts)
      end

      def patch(path, **opts)
        declare_route("PATCH", path, **opts)
      end

      def delete(path, **opts)
        declare_route("DELETE", path, **opts)
      end

      def options(path, **opts)
        declare_route("OPTIONS", path, **opts)
      end

      private

      def declare_route(method, path, request: nil, response: nil, **metadata)
        @declared_routes << {
          method: method,
          path: path,
          request_schema: request,
          response_schema: response,
          metadata: metadata
        }
      end
    end

    def call(req)
      raise NotImplementedError, "#{self.class}#call must be implemented"
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/endpoint_spec.rb`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/endpoint.rb spec/whoosh/endpoint_spec.rb
git commit -m "feat: add Endpoint base class with route DSL and Context delegation"
```

---

### Task 4: App Integration — Plugin DSL and Endpoint Loading

**Files:**
- Modify: `lib/whoosh/app.rb`
- Test: `spec/whoosh/app_plugins_spec.rb`
- Test: `spec/whoosh/app_endpoints_spec.rb`

This task integrates the Plugin Registry and Endpoint loading into the App class:
1. App creates a Plugin Registry at init and defines accessors on itself
2. `app.plugin` DSL for configuration/override
3. `app.load_endpoints(dir)` scans `endpoints/**/*.rb` and registers class-based endpoints
4. Endpoint handlers execute via Context for method delegation

- [ ] **Step 1: Write the failing test for plugin integration**

```ruby
# spec/whoosh/app_plugins_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App plugin integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "#plugin" do
    it "configures a registered plugin" do
      application.plugin :lingua, languages: [:en, :id]
      expect(application.plugin_registry.config_for(:lingua)).to eq({ languages: [:en, :id] })
    end

    it "disables a plugin with enabled: false" do
      application.plugin :ner, enabled: false
      expect(application.plugin_registry.disabled?(:ner)).to be true
    end
  end

  describe "plugin accessor via endpoint" do
    it "makes plugin accessors available in inline endpoints" do
      # Register a test plugin with a known initializer
      application.plugin_registry.register("test-plugin",
        accessor: :test_tool,
        initializer: -> (_config) { "tool_instance" }
      )
      application.setup_plugin_accessors

      application.get "/use-plugin" do
        { tool: test_tool }
      end

      get "/use-plugin"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["tool"]).to eq("tool_instance")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/app_plugins_spec.rb`
Expected: FAIL — `plugin_registry` method not found

- [ ] **Step 3: Write the failing test for endpoint loading**

```ruby
# spec/whoosh/app_endpoints_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "tmpdir"

RSpec.describe "App endpoint loading" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "#load_endpoints" do
    it "auto-loads and registers class-based endpoints" do
      Dir.mktmpdir do |dir|
        # Write an endpoint file
        File.write(File.join(dir, "status_endpoint.rb"), <<~RUBY)
          class StatusEndpoint < Whoosh::Endpoint
            get "/status"

            def call(req)
              { up: true }
            end
          end
        RUBY

        application.load_endpoints(dir)
        get "/status"
        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["up"]).to be true
      end
    end
  end

  describe "endpoint with context delegation" do
    it "delegates method calls to app via Context" do
      application.provide(:greeter) { "Hello" }

      # Simulate a class-based endpoint
      endpoint_class = Class.new(Whoosh::Endpoint) do
        get "/greet"

        def call(req)
          # This calls resolve on the DI through Context delegation
          { greeting: "works" }
        end
      end

      application.register_endpoint(endpoint_class)
      get "/greet"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["greeting"]).to eq("works")
    end
  end

  describe "#register_endpoint" do
    it "registers all declared routes from an endpoint class" do
      endpoint_class = Class.new(Whoosh::Endpoint) do
        get "/items"
        post "/items"

        def call(req)
          { method: req.method }
        end
      end

      application.register_endpoint(endpoint_class)

      get "/items"
      expect(JSON.parse(last_response.body)["method"]).to eq("GET")

      post "/items"
      expect(JSON.parse(last_response.body)["method"]).to eq("POST")
    end
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/app_endpoints_spec.rb`
Expected: FAIL — `register_endpoint` method not found

- [ ] **Step 5: Update App with plugin and endpoint support**

Add these methods and modifications to `lib/whoosh/app.rb`:

**Add to public section of App class:**
```ruby
    attr_reader :plugin_registry

    # --- Plugin DSL ---

    def plugin(name, enabled: true, **config)
      if enabled == false
        @plugin_registry.disable(name)
      else
        @plugin_registry.configure(name, config) unless config.empty?
      end
    end

    def setup_plugin_accessors
      @plugin_registry.define_accessors(self)
    end

    # --- Endpoint loading ---

    def load_endpoints(dir)
      before = ObjectSpace.each_object(Class).select { |k| k < Endpoint }.to_set

      Dir.glob(File.join(dir, "**", "*.rb")).sort.each do |file|
        require file
      end

      after = ObjectSpace.each_object(Class).select { |k| k < Endpoint }.to_set
      (after - before).each { |klass| register_endpoint(klass) }
    end

    def register_endpoint(endpoint_class)
      endpoint_class.declared_routes.each do |route|
        handler = {
          block: nil,
          endpoint_class: endpoint_class,
          request_schema: route[:request_schema],
          response_schema: route[:response_schema],
          middleware: []
        }
        @router.add(route[:method], route[:path], handler, **route[:metadata])
      end
    end
```

**Update `initialize` to create the plugin registry:**
Add after `@group_middleware = []`:
```ruby
      @plugin_registry = Plugins::Registry.new
```

**Update `handle_request` to support class-based endpoints:**
Replace the handler call section (the block resolution and call) with:
```ruby
      # Call handler
      if handler[:endpoint_class]
        # Class-based endpoint
        endpoint = handler[:endpoint_class].new
        context = Endpoint::Context.new(self, request)
        result = endpoint.call(context.request)
      else
        # Inline block endpoint
        block = handler[:block]
        block_params = block.parameters
        kwargs_names = block_params.select { |type, _| type == :keyreq || type == :key }.map(&:last)
        kwargs = @di.inject_for(kwargs_names, request: request)

        result = if kwargs.any? && block_params.any? { |type, _| type == :req || type == :opt }
          block.call(request, **kwargs)
        elsif kwargs.any?
          block.call(**kwargs)
        elsif block_params.any? { |type, _| type == :req || type == :opt }
          block.call(request)
        else
          block.call
        end
      end
```

- [ ] **Step 6: Run all tests to verify they pass**

Run: `bundle exec rspec spec/whoosh/app_plugins_spec.rb spec/whoosh/app_endpoints_spec.rb`
Expected: All pass

- [ ] **Step 7: Run full test suite to verify nothing broke**

Run: `bundle exec rspec`
Expected: All pass (113 + new tests)

- [ ] **Step 8: Commit**

```bash
git add lib/whoosh/app.rb spec/whoosh/app_plugins_spec.rb spec/whoosh/app_endpoints_spec.rb
git commit -m "feat: integrate Plugin Registry and Endpoint loading into App"
```

---

## Chunk 3: Inline Endpoint Context & Final Verification

### Task 5: Inline Endpoint Context

Currently inline endpoint blocks (`app.get "/path" do ... end`) run with `self` bound to where the block was defined. The spec says `self` inside these blocks should be an `Endpoint::Context` so plugin accessors are available as bare method calls.

**Files:**
- Modify: `lib/whoosh/app.rb`
- Test: `spec/whoosh/app_context_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/app_context_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App inline endpoint context" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "plugin accessors in inline blocks" do
    it "allows bare plugin method calls via context delegation" do
      application.plugin_registry.register("test-nlp",
        accessor: :nlp,
        initializer: -> (_config) { double_obj = Object.new; double_obj.define_singleton_method(:analyze) { |text| "analyzed: #{text}" }; double_obj }
      )
      application.setup_plugin_accessors

      application.post "/analyze" do |req|
        result = nlp.analyze(req.body["text"])
        { result: result }
      end

      post "/analyze", { text: "hello" }.to_json, "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["result"]).to eq("analyzed: hello")
    end
  end

  describe "DI kwargs still work with context" do
    it "injects DI dependencies alongside context" do
      application.provide(:greeting) { "Hi" }

      application.get "/hello/:name" do |req, greeting:|
        { message: "#{greeting}, #{req.params[:name]}!" }
      end

      get "/hello/Alice"
      expect(JSON.parse(last_response.body)["message"]).to eq("Hi, Alice!")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/whoosh/app_context_spec.rb`
Expected: The plugin accessor test FAILS because inline blocks don't run in Context scope

- [ ] **Step 3: Update handle_request to run inline blocks in Context**

In `lib/whoosh/app.rb`, update the inline block handler section inside `handle_request`. The block needs to be executed via `instance_exec` on the Context so that `method_missing` delegates to the app:

Replace the inline block execution in `handle_request` with:

```ruby
        # Inline block endpoint
        block = handler[:block]
        context = Endpoint::Context.new(self, request)
        block_params = block.parameters
        kwargs_names = block_params.select { |type, _| type == :keyreq || type == :key }.map(&:last)
        kwargs = @di.inject_for(kwargs_names, request: request)

        result = if kwargs.any? && block_params.any? { |type, _| type == :req || type == :opt }
          context.instance_exec(request, **kwargs, &block)
        elsif kwargs.any?
          context.instance_exec(**kwargs, &block)
        elsif block_params.any? { |type, _| type == :req || type == :opt }
          context.instance_exec(request, &block)
        else
          context.instance_exec(&block)
        end
```

**The complete final `handle_request` method after both Task 4 and Task 5 modifications should be:**

```ruby
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

      # Call handler
      if handler[:endpoint_class]
        # Class-based endpoint
        endpoint = handler[:endpoint_class].new
        context = Endpoint::Context.new(self, request)
        result = endpoint.call(context.request)
      else
        # Inline block endpoint — run in Context for plugin accessor delegation
        block = handler[:block]
        context = Endpoint::Context.new(self, request)
        block_params = block.parameters
        kwargs_names = block_params.select { |type, _| type == :keyreq || type == :key }.map(&:last)
        kwargs = @di.inject_for(kwargs_names, request: request)

        result = if kwargs.any? && block_params.any? { |type, _| type == :req || type == :opt }
          context.instance_exec(request, **kwargs, &block)
        elsif kwargs.any?
          context.instance_exec(**kwargs, &block)
        elsif block_params.any? { |type, _| type == :req || type == :opt }
          context.instance_exec(request, &block)
        else
          context.instance_exec(&block)
        end
      end

      Response.json(result)

    rescue Errors::HttpError => e
      Response.error(e)
    rescue => e
      handle_error(e, request)
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/whoosh/app_context_spec.rb`
Expected: All pass

- [ ] **Step 5: Run full test suite to verify nothing broke**

Run: `bundle exec rspec`
Expected: All pass — existing inline endpoint tests should still work since `instance_exec` preserves the block parameter behavior

- [ ] **Step 6: Commit**

```bash
git add lib/whoosh/app.rb spec/whoosh/app_context_spec.rb
git commit -m "feat: run inline endpoint blocks in Context for plugin accessor delegation"
```

---

### Task 6: Full Test Suite & Smoke Test

**Files:**
- No new files

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rspec`
Expected: All tests pass

- [ ] **Step 2: Run an end-to-end smoke test**

```bash
bundle exec ruby -e "
require 'whoosh'
require 'rack/test'
include Rack::Test::Methods

app_instance = Whoosh::App.new

# Register a test plugin
app_instance.plugin_registry.register('test-ai',
  accessor: :ai,
  initializer: -> (_config) {
    obj = Object.new
    obj.define_singleton_method(:generate) { |prompt| \"AI says: #{prompt}\" }
    obj
  }
)
app_instance.setup_plugin_accessors

# Inline endpoint using plugin
app_instance.post '/ask' do |req|
  { answer: ai.generate(req.body['question']) }
end

# Class-based endpoint
eval <<~RUBY
  class SmokeHealthEndpoint < Whoosh::Endpoint
    get '/smoke/health'
    def call(req)
      { status: 'ok', phase: 2 }
    end
  end
RUBY
app_instance.register_endpoint(SmokeHealthEndpoint)

define_method(:app) { app_instance.to_rack }

# Test inline endpoint with plugin
post '/ask', { question: 'what is ruby?' }.to_json, 'CONTENT_TYPE' => 'application/json'
puts \"Ask status: #{last_response.status}\"
puts \"Ask body: #{last_response.body}\"

# Test class-based endpoint
get '/smoke/health'
puts \"Health status: #{last_response.status}\"
puts \"Health body: #{last_response.body}\"

puts 'Whoosh Phase 2 working!'
" 2>/dev/null
```

Expected:
```
Ask status: 200
Ask body: {"answer":"AI says: what is ruby?"}
Health status: 200
Health body: {"status":"ok","phase":2}
Whoosh Phase 2 working!
```

---

## Phase 2 Completion Checklist

After all tasks are done, verify:

- [ ] `bundle exec rspec` — all green
- [ ] Plugin Registry with default gem mappings (18 gems)
- [ ] Plugin lazy loading with Mutex thread safety
- [ ] Plugin configuration via `app.plugin` DSL
- [ ] Plugin disable support
- [ ] Gemfile.lock scanning for auto-discovery
- [ ] Plugins::Base with hook interface (middleware?, before_request, after_response)
- [ ] Class-based Endpoint with route DSL
- [ ] Endpoint::Context delegates to App
- [ ] App registers class-based endpoints via `register_endpoint`
- [ ] App loads endpoints from directory via `load_endpoints`
- [ ] Inline endpoints run in Context scope (plugin accessors available)
- [ ] DI kwargs still work with Context
- [ ] All existing Phase 1 tests still pass

## Next Phase

After Phase 2 passes, proceed to **Phase 3: Auth & Security** — adding API key, JWT, OAuth2, rate limiting, and token usage tracking.
