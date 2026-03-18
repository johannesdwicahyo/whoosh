# lib/whoosh/cli/project_generator.rb
# frozen_string_literal: true

require "fileutils"
require "securerandom"

module Whoosh
  module CLI
    class ProjectGenerator
      def self.create(name, root: Dir.pwd, minimal: false, full: false)
        dir = File.join(root, name)
        FileUtils.mkdir_p(dir)
        %w[config endpoints schemas models middleware db/migrations test/endpoints].each do |d|
          FileUtils.mkdir_p(File.join(dir, d))
        end

        jwt_secret = SecureRandom.hex(32)

        write(dir, "app.rb", app_rb(name))
        write(dir, "config.ru", config_ru)
        write(dir, "Gemfile", gemfile(minimal: minimal, full: full))
        write(dir, "Rakefile", rakefile)
        write(dir, "config/app.yml", app_yml(name))
        write(dir, "config/plugins.yml", plugins_yml)
        write(dir, "endpoints/health.rb", health_endpoint)
        write(dir, "schemas/health.rb", health_schema)
        write(dir, "test/test_helper.rb", test_helper)
        write(dir, ".env", env_file(jwt_secret))
        write(dir, ".env.example", env_example)
        write(dir, ".gitignore", gitignore)
        write(dir, ".rspec", rspec_config)
        write(dir, "Dockerfile", dockerfile)
        write(dir, ".dockerignore", dockerignore)
        write(dir, ".rubocop.yml", rubocop_config)
        write(dir, "README.md", readme(name))
        write(dir, "CLAUDE.md", claude_md(name))

        # Create empty SQLite DB directory
        FileUtils.mkdir_p(File.join(dir, "db"))

        # Auto-run bundle install
        puts "Created #{name}/"
        puts ""
        Dir.chdir(dir) do
          puts "Installing dependencies..."
          system("bundle install --quiet")
        end
        puts ""
        puts "  #{name}/ is ready!"
        puts ""
        puts "  cd #{name}"
        puts "  whoosh s            # start server at http://localhost:9292"
        puts "  whoosh s --reload   # start with hot reload"
        puts ""
        puts "  http://localhost:9292/health    # health check"
        puts "  http://localhost:9292/healthz   # health probes"
        puts "  http://localhost:9292/docs      # Swagger UI"
        puts "  http://localhost:9292/metrics   # Prometheus metrics"
        puts ""
        puts "  whoosh ci           # run lint + security + tests"
        puts ""
      end

      class << self
        private

        def write(dir, path, content)
          File.write(File.join(dir, path), content)
        end

        def app_rb(name)
          <<~RUBY
            # frozen_string_literal: true

            require "whoosh"

            # Auto-enable YJIT + Oj for best performance
            Whoosh::Performance.optimize!

            App = Whoosh::App.new

            # --- API Documentation ---
            App.openapi do
              title "#{name.gsub(/[-_]/, " ").split.map(&:capitalize).join(" ")} API"
              version "0.1.0"
            end

            App.docs enabled: true, redoc: true

            # --- Security ---
            App.auth do
              jwt secret: ENV["JWT_SECRET"], algorithm: :hs256, expiry: 3600
            end

            App.rate_limit do
              default limit: 60, period: 60
            end

            # --- Health Check ---
            App.health_check do
              probe(:api) { true }
            end

            # --- Load Endpoints ---
            App.load_endpoints(File.join(__dir__, "endpoints"))
          RUBY
        end

        def config_ru
          <<~RUBY
            # frozen_string_literal: true

            require_relative "app"

            run App.to_rack
          RUBY
        end

        def gemfile(minimal: false, full: false)
          g = <<~GEM
            source "https://rubygems.org"

            gem "whoosh"

            # Server (Falcon recommended for best performance)
            gem "falcon"

            # Fast JSON (5-10x faster than stdlib)
            gem "oj"

            # Database
            gem "sequel"
            gem "sqlite3"
          GEM

          if full
            g += <<~GEM

              # AI & NLP
              gem "ruby_llm"
              gem "lingua-ruby"
              gem "ner-ruby"
              gem "guardrails-ruby"
            GEM
          end

          g += <<~GEM

            group :development, :test do
              gem "rspec"
              gem "rack-test"
              gem "rubocop", require: false
              gem "brakeman", require: false
              gem "bundler-audit", require: false
              gem "simplecov", require: false
            end
          GEM

          g
        end

        def rakefile
          <<~RUBY
            require "rspec/core/rake_task"
            RSpec::Core::RakeTask.new(:spec)
            task default: :spec
          RUBY
        end

        def app_yml(name)
          <<~YAML
            app:
              name: "#{name.gsub(/[-_]/, " ").split.map(&:capitalize).join(" ")} API"
              port: 9292
              host: localhost

            server:
              type: falcon
              workers: auto

            database:
              url: <%= ENV.fetch("DATABASE_URL", "sqlite://db/development.sqlite3") %>
              max_connections: 10
              log_level: debug

            # Cache & Jobs auto-detect:
            # No REDIS_URL → in-memory (just works)
            # Set REDIS_URL → auto-switches to Redis
            cache:
              default_ttl: 300

            jobs:
              backend: memory
              workers: 2
              retry: 3

            logging:
              level: info
              format: json

            # Vector store auto-detect:
            # zvec gem installed → uses zvec, otherwise → in-memory
            # vector:
            #   adapter: auto
            #   path: db/vectors

            docs:
              enabled: true

            performance:
              yjit: true
          YAML
        end

        def plugins_yml
          <<~YAML
            # Plugin configuration
            # Gems are auto-discovered from Gemfile.lock
            # Configure or disable here:
            #
            # lingua:
            #   languages: [en, id, ms]
            #
            # guardrails:
            #   language_check:
            #     enabled: true
            #
            # ner:
            #   enabled: false
          YAML
        end

        def health_endpoint
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

        def health_schema
          <<~RUBY
            # frozen_string_literal: true

            class HealthResponse < Whoosh::Schema
              field :status, String, required: true, desc: "Health status"
              field :version, String, desc: "API version"
            end
          RUBY
        end

        def test_helper
          <<~RUBY
            # frozen_string_literal: true

            require "simplecov"
            SimpleCov.start do
              add_filter "/test/"
              add_filter "/spec/"
              minimum_coverage 80
            end

            require "whoosh/test"
            require_relative "../app"

            RSpec.configure do |config|
              config.include Whoosh::Test

              def app
                App.to_rack
              end
            end
          RUBY
        end

        def env_file(jwt_secret)
          <<~ENV
            # Generated by whoosh new — do NOT commit this file
            JWT_SECRET=#{jwt_secret}
            WHOOSH_ENV=development
            DATABASE_URL=sqlite://db/development.sqlite3
          ENV
        end

        def env_example
          <<~ENV
            # Copy to .env and fill in values
            JWT_SECRET=change_me_to_a_random_64_char_hex
            WHOOSH_ENV=development
            DATABASE_URL=sqlite://db/development.sqlite3
            # REDIS_URL=redis://localhost:6379
          ENV
        end

        def gitignore
          <<~GIT
            # Dependencies
            /vendor/bundle
            /.bundle

            # Environment
            .env
            .env.local
            .env.production

            # Database
            db/*.sqlite3

            # Logs
            /log/*
            /tmp/*

            # OS
            .DS_Store
            *.swp
            *~

            # IDE
            .idea/
            .vscode/
            *.code-workspace

            # Gems
            *.gem
            Gemfile.lock
          GIT
        end

        def rspec_config
          <<~RSPEC
            --require spec_helper
            --format documentation
            --color
            --order random
          RSPEC
        end

        def dockerfile
          <<~DOCKERFILE
            FROM ruby:3.4-slim

            WORKDIR /app

            # Install system dependencies
            RUN apt-get update -qq && apt-get install -y build-essential libsqlite3-dev

            # Install gems
            COPY Gemfile Gemfile.lock ./
            RUN bundle install --without development test

            # Copy app
            COPY . .

            EXPOSE 9292

            # Start with Falcon for best performance
            CMD ["bundle", "exec", "whoosh", "s", "-p", "9292", "--host", "0.0.0.0"]
          DOCKERFILE
        end

        def rubocop_config
          <<~YAML
            AllCops:
              TargetRubyVersion: 3.4
              NewCops: enable
              SuggestExtensions: false
              Exclude:
                - db/migrations/**/*
                - vendor/**/*

            Style/FrozenStringLiteralComment:
              Enabled: true

            Style/StringLiterals:
              EnforcedStyle: double_quotes

            Layout/LineLength:
              Max: 120

            Metrics/MethodLength:
              Max: 25

            Metrics/BlockLength:
              Exclude:
                - spec/**/*
                - test/**/*
          YAML
        end

        def dockerignore
          <<~IGNORE
            .git
            .env
            .env.*
            node_modules
            tmp
            log
            db/*.sqlite3
            *.gem
            .DS_Store
          IGNORE
        end

        def claude_md(name)
          title = name.gsub(/[-_]/, " ").split.map(&:capitalize).join(" ")
          <<~MD
            # #{title}

            ## Framework

            Built with [Whoosh](https://github.com/johannesdwicahyo/whoosh) — AI-first Ruby API framework.

            ## Commands

            ```bash
            whoosh s                    # start server (http://localhost:9292)
            whoosh s --reload           # hot reload on file changes
            whoosh ci                   # run lint + security + tests
            whoosh routes               # list all routes
            whoosh describe             # dump app structure as JSON
            whoosh check                # validate configuration
            whoosh console              # IRB with app loaded
            whoosh mcp --list           # list MCP tools
            whoosh worker               # start background job worker
            bundle exec rspec           # run tests
            ```

            ## Project Structure

            ```
            app.rb              # main app — routes, auth, config
            config.ru           # Rack entry point
            config/app.yml      # configuration (database, cache, jobs, logging)
            config/plugins.yml  # plugin configuration
            endpoints/          # class-based endpoints (auto-loaded)
            schemas/            # request/response schemas (dry-schema)
            models/             # Sequel models
            db/migrations/      # database migrations
            middleware/         # custom middleware
            test/               # RSpec tests
            .env                # secrets (never commit)
            ```

            ## Patterns

            ### Adding an endpoint

            ```bash
            whoosh generate endpoint users name:string email:string
            ```

            Or manually:

            ```ruby
            # endpoints/users.rb
            class UsersEndpoint < Whoosh::Endpoint
              get "/users"
              post "/users", request: CreateUserSchema

              def call(req)
                case req.method
                when "GET" then { users: [] }
                when "POST" then { created: true }
                end
              end
            end
            ```

            ### Adding a schema

            ```ruby
            # schemas/user.rb
            class CreateUserSchema < Whoosh::Schema
              field :name,  String,  required: true, desc: "User name"
              field :email, String,  required: true, desc: "Email"
              field :age,   Integer, min: 0, max: 150
            end
            ```

            ### Inline routes (in app.rb)

            ```ruby
            App.get "/health" do
              { status: "ok" }
            end

            App.post "/items", request: ItemSchema, auth: :api_key do |req|
              { created: req.body[:name] }
            end
            ```

            ### Auth

            Protected routes use `auth: :api_key` or `auth: :jwt`:
            ```ruby
            App.get "/protected", auth: :api_key do |req|
              { user: req.env["whoosh.auth"][:key] }
            end
            ```

            ### Background jobs

            ```ruby
            class MyJob < Whoosh::Job
              inject :db  # DI injection
              queue :default
              retry_limit 3
              retry_backoff :exponential

              def perform(user_id:)
                { done: true }
              end
            end

            MyJob.perform_async(user_id: 42)
            MyJob.perform_in(3600, user_id: 42)  # 1 hour delay
            ```

            ### Streaming (SSE/LLM)

            ```ruby
            App.post "/chat" do |req|
              stream_llm do |out|
                out << "Hello "
                out << "World"
                out.finish
              end
            end
            ```

            ### MCP tools

            Routes with `mcp: true` are auto-exposed as MCP tools:
            ```ruby
            App.post "/analyze", mcp: true, request: AnalyzeSchema do |req|
              { result: "analyzed" }
            end
            ```

            ### Testing

            ```ruby
            require "whoosh/test"
            RSpec.describe "API" do
              include Whoosh::Test
              def app = App.to_rack

              it "works" do
                post_json "/items", { name: "test" }
                assert_response 200
                assert_json(name: "test")
              end
            end
            ```

            ## AI Introspection

            ```bash
            whoosh describe              # full app structure as JSON
            whoosh describe --routes     # routes with schemas
            whoosh describe --schemas    # all schema definitions
            ```

            ## Configuration

            All config in `config/app.yml`. Environment variables override YAML.
            Secrets in `.env` (auto-loaded at boot, never committed).

            ## Response Format

            Simple flat JSON. Not JSON:API.
            - Success: `{"name": "Alice"}`
            - Error: `{"error": "validation_failed", "details": [...]}`
            - Pagination: `{"data": [...], "pagination": {"page": 1}}`
          MD
        end

        def readme(name)
          title = name.gsub(/[-_]/, " ").split.map(&:capitalize).join(" ")
          <<~MD
            # #{title} API

            Built with [Whoosh](https://github.com/johannesdwicahyo/whoosh) — AI-first Ruby API framework.

            ## Quick Start

            ```bash
            whoosh s              # http://localhost:9292
            whoosh s --reload     # hot reload
            ```

            ## Endpoints

            | Method | Path | Description |
            |--------|------|-------------|
            | GET | /health | Health check |
            | GET | /healthz | Health probes |
            | GET | /docs | Swagger UI |
            | GET | /redoc | ReDoc |
            | GET | /openapi.json | OpenAPI spec |
            | GET | /metrics | Prometheus metrics |

            ## Development

            ```bash
            whoosh generate endpoint users       # create endpoint + schema + test
            whoosh generate schema CreateUser     # create schema
            whoosh generate model User name:string email:string
            whoosh routes                         # list all routes
            whoosh console                        # IRB with app loaded
            bundle exec rspec                     # run tests
            ```

            ## Deploy

            ```bash
            docker build -t #{name} .
            docker run -p 9292:9292 -e JWT_SECRET=your_secret #{name}
            ```
          MD
        end
      end
    end
  end
end
