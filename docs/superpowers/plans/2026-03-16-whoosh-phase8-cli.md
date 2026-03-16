# Whoosh Phase 8: CLI Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Thor-based CLI with commands: `new` (project scaffold), `server` (start Falcon/Puma), `routes` (list routes), `generate` (endpoint/schema/model/migration), `console` (IRB), `mcp` (stdio/SSE/list), and `db` (migrate/rollback/status).

**Architecture:** `CLI::Main` is the Thor entry point dispatched from `exe/whoosh`. Each command is a separate class under `CLI::Commands::`. Templates for generators use ERB (`.erb` suffix). The `new` command creates a full project scaffold.

**Tech Stack:** Ruby 3.4+, Thor ~> 1.3, RSpec. Thor is already a hard dependency.

**Spec:** `docs/superpowers/specs/2026-03-11-whoosh-design.md` (CLI section lines 608-670)

**Depends on:** Phase 1-7 complete (253 tests passing).

---

## Chunk 1: CLI Main and Core Commands

### Task 1: CLI Main Entry Point

**Files:**
- Create: `lib/whoosh/cli/main.rb`
- Modify: `exe/whoosh`
- Test: `spec/whoosh/cli/main_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/cli/main_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh/cli/main"

RSpec.describe Whoosh::CLI::Main do
  describe "version" do
    it "prints the version" do
      output = capture_output { Whoosh::CLI::Main.start(["version"]) }
      expect(output).to include(Whoosh::VERSION)
    end
  end

  describe "routes" do
    it "is a registered command" do
      expect(Whoosh::CLI::Main.all_commands).to have_key("routes")
    end
  end

  describe "server" do
    it "is a registered command" do
      expect(Whoosh::CLI::Main.all_commands).to have_key("server")
    end
  end

  private

  def capture_output
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/cli/main.rb
# frozen_string_literal: true

require "thor"
require "whoosh"

module Whoosh
  module CLI
    class Main < Thor
      desc "version", "Print Whoosh version"
      def version
        puts "Whoosh v#{Whoosh::VERSION}"
      end

      desc "server", "Start the Whoosh server"
      option :port, aliases: "-p", type: :numeric, default: 9292, desc: "Port number"
      option :host, type: :string, default: "localhost", desc: "Host to bind to"
      option :reload, type: :boolean, default: false, desc: "Auto-reload on changes"
      def server
        app_file = File.join(Dir.pwd, "config.ru")
        unless File.exist?(app_file)
          puts "Error: config.ru not found in #{Dir.pwd}"
          exit 1
        end

        port = options[:port]
        host = options[:host]
        puts "Starting Whoosh server on #{host}:#{port}..."

        # Use rackup to start the server
        exec("bundle exec rackup #{app_file} -p #{port} -o #{host}")
      end

      desc "routes", "List all registered routes"
      def routes
        app_file = File.join(Dir.pwd, "app.rb")
        unless File.exist?(app_file)
          puts "Error: app.rb not found in #{Dir.pwd}"
          exit 1
        end

        require app_file
        app = find_whoosh_app

        if app
          route_list = app.routes
          if route_list.empty?
            puts "No routes registered."
          else
            puts "Routes:"
            route_list.each do |route|
              puts "  #{route[:method].ljust(8)} #{route[:path]}"
            end
          end
        else
          puts "Error: No Whoosh::App instance found"
        end
      end

      desc "console", "Start an interactive console with the app loaded"
      def console
        app_file = File.join(Dir.pwd, "app.rb")
        if File.exist?(app_file)
          require app_file
        end

        require "irb"
        IRB.start
      end

      desc "mcp", "Start MCP server"
      option :sse, type: :boolean, default: false, desc: "Use SSE transport"
      option :list, type: :boolean, default: false, desc: "List MCP tools"
      def mcp
        app_file = File.join(Dir.pwd, "app.rb")
        unless File.exist?(app_file)
          puts "Error: app.rb not found"
          exit 1
        end

        require app_file
        app = find_whoosh_app
        unless app
          puts "Error: No Whoosh::App instance found"
          exit 1
        end

        # Build the rack app to register MCP tools
        app.to_rack

        if options[:list]
          tools = app.mcp_server.list_tools
          if tools.empty?
            puts "No MCP tools registered."
          else
            puts "MCP Tools:"
            tools.each { |t| puts "  #{t[:name]} - #{t[:description]}" }
          end
          return
        end

        # Stdio transport
        puts "Whoosh MCP server running (stdio)..."
        run_mcp_stdio(app.mcp_server)
      end

      desc "generate SUBCOMMAND", "Generate components"
      subcommand "generate", Class.new(Thor) {
        namespace "generate"

        desc "endpoint NAME", "Generate an endpoint with schema and test"
        def endpoint(name)
          Whoosh::CLI::Generators.endpoint(name)
        end

        desc "schema NAME", "Generate a schema file"
        def schema(name)
          Whoosh::CLI::Generators.schema(name)
        end

        desc "model NAME [FIELDS...]", "Generate a model with migration"
        def model(name, *fields)
          Whoosh::CLI::Generators.model(name, fields)
        end

        desc "migration NAME", "Generate a blank migration"
        def migration(name)
          Whoosh::CLI::Generators.migration(name)
        end
      }

      desc "new NAME", "Create a new Whoosh project"
      option :minimal, type: :boolean, default: false, desc: "Minimal project"
      option :full, type: :boolean, default: false, desc: "Full project with all gems"
      def new(name)
        Whoosh::CLI::ProjectGenerator.create(name, minimal: options[:minimal], full: options[:full])
      end

      private

      def find_whoosh_app
        ObjectSpace.each_object(Whoosh::App).first
      end

      def run_mcp_stdio(mcp_server)
        $stdin.each_line do |line|
          next if line.strip.empty?
          begin
            request = Whoosh::MCP::Protocol.parse(line)
            response = mcp_server.handle(request)
            if response
              $stdout.puts(Whoosh::MCP::Protocol.encode(response))
              $stdout.flush
            end
          rescue Whoosh::MCP::Protocol::ParseError => e
            error = Whoosh::MCP::Protocol.error_response(id: nil, code: -32700, message: e.message)
            $stdout.puts(Whoosh::MCP::Protocol.encode(error))
            $stdout.flush
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Update exe/whoosh**

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "whoosh/cli/main"

Whoosh::CLI::Main.start(ARGV)
```

- [ ] **Step 5: Run test to verify it passes**

- [ ] **Step 6: Commit**

```bash
git add lib/whoosh/cli/main.rb exe/whoosh spec/whoosh/cli/main_spec.rb
git commit -m "feat: add CLI main entry point with server, routes, console, and mcp commands"
```

---

### Task 2: Project Generator (`whoosh new`)

**Files:**
- Create: `lib/whoosh/cli/project_generator.rb`
- Test: `spec/whoosh/cli/project_generator_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/cli/project_generator_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh/cli/project_generator"
require "tmpdir"

RSpec.describe Whoosh::CLI::ProjectGenerator do
  describe ".create" do
    it "creates a project directory structure" do
      Dir.mktmpdir do |dir|
        project_path = File.join(dir, "myapp")
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)

        expect(File.directory?(project_path)).to be true
        expect(File.exist?(File.join(project_path, "app.rb"))).to be true
        expect(File.exist?(File.join(project_path, "config.ru"))).to be true
        expect(File.exist?(File.join(project_path, "Gemfile"))).to be true
        expect(File.exist?(File.join(project_path, "config", "app.yml"))).to be true
        expect(File.directory?(File.join(project_path, "endpoints"))).to be true
        expect(File.directory?(File.join(project_path, "schemas"))).to be true
        expect(File.directory?(File.join(project_path, "db", "migrations"))).to be true
      end
    end

    it "generates a valid app.rb" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        content = File.read(File.join(dir, "myapp", "app.rb"))
        expect(content).to include("Whoosh::App.new")
        expect(content).to include("require \"whoosh\"")
      end
    end

    it "generates a valid config.ru" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        content = File.read(File.join(dir, "myapp", "config.ru"))
        expect(content).to include("run")
        expect(content).to include("to_rack")
      end
    end

    it "generates a health endpoint" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        content = File.read(File.join(dir, "myapp", "endpoints", "health.rb"))
        expect(content).to include("Whoosh::Endpoint")
        expect(content).to include("/health")
      end
    end

    it "generates a Gemfile with whoosh" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        content = File.read(File.join(dir, "myapp", "Gemfile"))
        expect(content).to include("whoosh")
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/cli/project_generator.rb
# frozen_string_literal: true

require "fileutils"

module Whoosh
  module CLI
    class ProjectGenerator
      def self.create(name, root: Dir.pwd, minimal: false, full: false)
        project_dir = File.join(root, name)
        FileUtils.mkdir_p(project_dir)

        # Create directories
        %w[config endpoints schemas models middleware db/migrations test/endpoints].each do |dir|
          FileUtils.mkdir_p(File.join(project_dir, dir))
        end

        write_file(project_dir, "app.rb", app_template(name))
        write_file(project_dir, "config.ru", config_ru_template)
        write_file(project_dir, "Gemfile", gemfile_template(full: full))
        write_file(project_dir, "Rakefile", rakefile_template)
        write_file(project_dir, "config/app.yml", app_yml_template(name))
        write_file(project_dir, "endpoints/health.rb", health_endpoint_template)
        write_file(project_dir, "schemas/health.rb", health_schema_template)
        write_file(project_dir, "test/test_helper.rb", test_helper_template)
        write_file(project_dir, ".env.example", env_example_template)

        puts "Created #{name}/ — run `cd #{name} && bundle install && whoosh server`"
      end

      class << self
        private

        def write_file(dir, path, content)
          File.write(File.join(dir, path), content)
        end

        def app_template(name)
          <<~RUBY
            # frozen_string_literal: true

            require "whoosh"

            App = Whoosh::App.new

            App.openapi do
              title "#{name.capitalize} API"
              version "0.1.0"
            end

            # Load endpoints from endpoints/ directory
            App.load_endpoints(File.join(__dir__, "endpoints"))
          RUBY
        end

        def config_ru_template
          <<~RUBY
            # frozen_string_literal: true

            require_relative "app"

            run App.to_rack
          RUBY
        end

        def gemfile_template(full: false)
          gems = <<~RUBY
            source "https://rubygems.org"

            gem "whoosh"
          RUBY

          if full
            gems += <<~RUBY

              # AI & NLP
              gem "ruby_llm"
              gem "lingua-ruby"
              gem "ner-ruby"
              gem "keyword-ruby"
              gem "guardrails-ruby"

              # Database
              gem "sequel"
              gem "sqlite3"
            RUBY
          end

          gems += <<~RUBY

            group :development, :test do
              gem "rspec"
              gem "rack-test"
            end
          RUBY

          gems
        end

        def rakefile_template
          <<~RUBY
            require "rspec/core/rake_task"
            RSpec::Core::RakeTask.new(:spec)
            task default: :spec
          RUBY
        end

        def app_yml_template(name)
          <<~YAML
            app:
              name: "#{name.capitalize} API"
              port: 9292
              host: localhost

            logging:
              level: info
              format: json

            docs:
              enabled: true
          YAML
        end

        def health_endpoint_template
          <<~RUBY
            # frozen_string_literal: true

            class HealthEndpoint < Whoosh::Endpoint
              get "/health"

              def call(req)
                { status: "ok", version: Whoosh::VERSION }
              end
            end
          RUBY
        end

        def health_schema_template
          <<~RUBY
            # frozen_string_literal: true

            class HealthResponse < Whoosh::Schema
              field :status, String, required: true, desc: "Health status"
              field :version, String, desc: "API version"
            end
          RUBY
        end

        def test_helper_template
          <<~RUBY
            # frozen_string_literal: true

            require "rack/test"
            require_relative "../app"

            RSpec.configure do |config|
              config.include Rack::Test::Methods
            end
          RUBY
        end

        def env_example_template
          <<~ENV
            # WHOOSH_PORT=9292
            # WHOOSH_ENV=development
            # DATABASE_URL=sqlite://db/development.sqlite3
          ENV
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/cli/project_generator.rb spec/whoosh/cli/project_generator_spec.rb
git commit -m "feat: add project generator for whoosh new with full scaffold"
```

---

## Chunk 2: Code Generators

### Task 3: Component Generators

**Files:**
- Create: `lib/whoosh/cli/generators.rb`
- Test: `spec/whoosh/cli/generators_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/whoosh/cli/generators_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh/cli/generators"
require "tmpdir"

RSpec.describe Whoosh::CLI::Generators do
  describe ".endpoint" do
    it "generates endpoint, schema, and test files" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::Generators.endpoint("chat", root: dir)

        expect(File.exist?(File.join(dir, "endpoints", "chat.rb"))).to be true
        expect(File.exist?(File.join(dir, "schemas", "chat.rb"))).to be true
        expect(File.exist?(File.join(dir, "test", "endpoints", "chat_test.rb"))).to be true

        content = File.read(File.join(dir, "endpoints", "chat.rb"))
        expect(content).to include("ChatEndpoint")
        expect(content).to include("Whoosh::Endpoint")
      end
    end
  end

  describe ".schema" do
    it "generates a schema file" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::Generators.schema("user", root: dir)
        expect(File.exist?(File.join(dir, "schemas", "user.rb"))).to be true
        content = File.read(File.join(dir, "schemas", "user.rb"))
        expect(content).to include("UserSchema")
        expect(content).to include("Whoosh::Schema")
      end
    end
  end

  describe ".model" do
    it "generates model and migration files" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::Generators.model("user", ["name:string", "email:string"], root: dir)

        expect(File.exist?(File.join(dir, "models", "user.rb"))).to be true

        migration_files = Dir.glob(File.join(dir, "db", "migrations", "*_create_users.rb"))
        expect(migration_files.length).to eq(1)

        model_content = File.read(File.join(dir, "models", "user.rb"))
        expect(model_content).to include("class User")
      end
    end
  end

  describe ".migration" do
    it "generates a blank migration file" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::Generators.migration("add_age_to_users", root: dir)
        files = Dir.glob(File.join(dir, "db", "migrations", "*_add_age_to_users.rb"))
        expect(files.length).to eq(1)
        content = File.read(files.first)
        expect(content).to include("Sequel.migration")
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write implementation**

```ruby
# lib/whoosh/cli/generators.rb
# frozen_string_literal: true

require "fileutils"

module Whoosh
  module CLI
    class Generators
      def self.endpoint(name, root: Dir.pwd)
        class_name = classify(name)

        FileUtils.mkdir_p(File.join(root, "endpoints"))
        FileUtils.mkdir_p(File.join(root, "schemas"))
        FileUtils.mkdir_p(File.join(root, "test", "endpoints"))

        File.write(File.join(root, "endpoints", "#{name}.rb"), <<~RUBY)
          # frozen_string_literal: true

          class #{class_name}Endpoint < Whoosh::Endpoint
            post "/#{name}", request: #{class_name}Request

            def call(req)
              { message: "#{class_name} endpoint" }
            end
          end
        RUBY

        File.write(File.join(root, "schemas", "#{name}.rb"), <<~RUBY)
          # frozen_string_literal: true

          class #{class_name}Request < Whoosh::Schema
            # Add fields here
          end

          class #{class_name}Response < Whoosh::Schema
            # Add fields here
          end
        RUBY

        File.write(File.join(root, "test", "endpoints", "#{name}_test.rb"), <<~RUBY)
          # frozen_string_literal: true

          require "test_helper"

          RSpec.describe #{class_name}Endpoint do
            it "responds to POST /#{name}" do
              post "/#{name}"
              expect(last_response.status).to eq(200)
            end
          end
        RUBY

        puts "Created endpoints/#{name}.rb, schemas/#{name}.rb, test/endpoints/#{name}_test.rb"
      end

      def self.schema(name, root: Dir.pwd)
        class_name = classify(name)
        FileUtils.mkdir_p(File.join(root, "schemas"))

        File.write(File.join(root, "schemas", "#{name}.rb"), <<~RUBY)
          # frozen_string_literal: true

          class #{class_name}Schema < Whoosh::Schema
            # Add fields here
            # field :name, String, required: true, desc: "Description"
          end
        RUBY

        puts "Created schemas/#{name}.rb"
      end

      def self.model(name, fields = [], root: Dir.pwd)
        class_name = classify(name)
        table_name = "#{name.downcase}s"
        timestamp = Time.now.strftime("%Y%m%d%H%M%S")

        FileUtils.mkdir_p(File.join(root, "models"))
        FileUtils.mkdir_p(File.join(root, "db", "migrations"))

        File.write(File.join(root, "models", "#{name.downcase}.rb"), <<~RUBY)
          # frozen_string_literal: true

          class #{class_name} < Sequel::Model(:#{table_name})
          end
        RUBY

        columns = fields.map do |f|
          col_name, col_type = f.split(":")
          sequel_type = case col_type
          when "string" then "String"
          when "integer" then "Integer"
          when "float" then "Float"
          when "boolean" then "TrueClass"
          when "text" then "String, text: true"
          when "datetime" then "DateTime"
          else "String"
          end
          "        #{sequel_type} :#{col_name}, null: false"
        end.join("\n")

        File.write(File.join(root, "db", "migrations", "#{timestamp}_create_#{table_name}.rb"), <<~RUBY)
          Sequel.migration do
            change do
              create_table(:#{table_name}) do
                primary_key :id
          #{columns}
                DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
                DateTime :updated_at
              end
            end
          end
        RUBY

        puts "Created models/#{name.downcase}.rb, db/migrations/#{timestamp}_create_#{table_name}.rb"
      end

      def self.migration(name, root: Dir.pwd)
        timestamp = Time.now.strftime("%Y%m%d%H%M%S")
        FileUtils.mkdir_p(File.join(root, "db", "migrations"))

        File.write(File.join(root, "db", "migrations", "#{timestamp}_#{name}.rb"), <<~RUBY)
          Sequel.migration do
            change do
              # Add migration code here
            end
          end
        RUBY

        puts "Created db/migrations/#{timestamp}_#{name}.rb"
      end

      def self.classify(name)
        name.split(/[-_]/).map(&:capitalize).join
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Commit**

```bash
git add lib/whoosh/cli/generators.rb spec/whoosh/cli/generators_spec.rb
git commit -m "feat: add component generators for endpoint, schema, model, and migration"
```

---

### Task 4: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 2: Smoke test CLI**

```bash
bundle exec ruby exe/whoosh version
```

Expected: `Whoosh v0.1.0`

```bash
bundle exec ruby -e "
require 'whoosh/cli/project_generator'
require 'tmpdir'

Dir.mktmpdir do |dir|
  Whoosh::CLI::ProjectGenerator.create('testapp', root: dir)
  puts Dir.glob(File.join(dir, 'testapp', '**', '*')).sort.map { |f| f.sub(dir + '/', '') }
end
"
```

---

## Phase 8 Completion Checklist

- [ ] `bundle exec rspec` — all green
- [ ] CLI main entry with Thor (version, server, routes, console, mcp)
- [ ] `whoosh new` generates full project scaffold
- [ ] `whoosh generate endpoint` creates endpoint + schema + test
- [ ] `whoosh generate schema` creates schema file
- [ ] `whoosh generate model` creates model + migration
- [ ] `whoosh generate migration` creates blank migration
- [ ] `whoosh mcp --list` lists MCP tools
- [ ] `exe/whoosh` dispatches to CLI::Main
- [ ] All Phase 1-7 tests still pass

## ALL PHASES COMPLETE

After Phase 8, the Whoosh framework is feature-complete for v0.1.0.
