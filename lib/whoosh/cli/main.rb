# frozen_string_literal: true

require "thor"
require "whoosh"
require "rack"
require "rack/builder"

module Whoosh
  module CLI
    class Main < Thor
      desc "version", "Print Whoosh version"
      def version
        puts "Whoosh v#{Whoosh::VERSION}"
      end

      desc "server", "Start the Whoosh server"
      option :port, aliases: "-p", type: :numeric, default: 9292, desc: "Port number"
      option :host, aliases: "-h", type: :string, default: "localhost", desc: "Host to bind"
      option :reload, type: :boolean, default: false, desc: "Restart server on file changes"
      map "s" => :server
      def server
        app_file = File.join(Dir.pwd, "app.rb")
        config_ru = File.join(Dir.pwd, "config.ru")

        unless File.exist?(app_file) || File.exist?(config_ru)
          puts "Error: No app.rb or config.ru found in #{Dir.pwd}"
          exit 1
        end

        port = options[:port]
        host = options[:host]

        puts "=> Whoosh v#{Whoosh::VERSION} starting..."
        puts "=> http://#{host}:#{port}"
        puts "=> Ctrl-C to stop"
        puts ""

        if options[:reload]
          puts "=> Watching for file changes (polling)..."
          pid = nil

          start = -> {
            pid = Process.spawn(
              {"WHOOSH_PORT" => port.to_s, "WHOOSH_HOST" => host},
              RbConfig.ruby, "-e",
              "require 'rackup'; app, _ = Rack::Builder.parse_file('#{config_ru || "config.ru"}'); Rackup::Server.start(app: app, Port: #{port}, Host: '#{host}')"
            )
          }

          start.call
          trap("INT") { Process.kill("TERM", pid) rescue nil; exit 0 }
          trap("TERM") { Process.kill("TERM", pid) rescue nil; exit 0 }

          mtimes = {}
          loop do
            sleep 1.5
            changed = false
            Dir.glob("{**/*.rb,config/**/*.yml}").each do |f|
              mt = File.mtime(f) rescue next
              if mtimes[f] && mtimes[f] != mt
                puts "=> Changed: #{f}, restarting..."
                changed = true
              end
              mtimes[f] = mt
            end
            if changed
              Process.kill("TERM", pid) rescue nil
              Process.wait(pid) rescue nil
              start.call
            end
          end
          return
        end

        # Load the app
        if File.exist?(config_ru)
          rack_app, _ = Rack::Builder.parse_file(config_ru)
        else
          require app_file
          whoosh_app = ObjectSpace.each_object(Whoosh::App).first
          unless whoosh_app
            puts "Error: No Whoosh::App instance found in app.rb"
            exit 1
          end
          rack_app = whoosh_app.to_rack
        end

        # Start server — try Falcon first, then Puma, then WEBrick
        require "rackup"
        Rackup::Server.start(app: rack_app, Port: port, Host: host)
      end

      desc "routes", "List all registered routes"
      def routes
        app_file = File.join(Dir.pwd, "app.rb")
        unless File.exist?(app_file)
          puts "Error: app.rb not found in #{Dir.pwd}"
          exit 1
        end
        require app_file
        app = ObjectSpace.each_object(Whoosh::App).first
        if app
          app.routes.each { |r| puts "  #{r[:method].ljust(8)} #{r[:path]}" }
        else
          puts "No Whoosh::App instance found"
        end
      end

      desc "console", "Start an interactive console with the app loaded"
      def console
        app_file = File.join(Dir.pwd, "app.rb")
        require app_file if File.exist?(app_file)
        require "irb"
        IRB.start
      end

      desc "mcp", "Start MCP server"
      option :sse, type: :boolean, default: false
      option :list, type: :boolean, default: false
      def mcp
        app_file = File.join(Dir.pwd, "app.rb")
        unless File.exist?(app_file)
          puts "Error: app.rb not found"
          exit 1
        end
        require app_file
        app = ObjectSpace.each_object(Whoosh::App).first
        unless app
          puts "No Whoosh::App instance found"
          exit 1
        end
        app.to_rack

        if options[:list]
          app.mcp_server.list_tools.each { |t| puts "  #{t[:name]} - #{t[:description]}" }
          return
        end

        $stdin.each_line do |line|
          next if line.strip.empty?
          begin
            request = MCP::Protocol.parse(line)
            response = app.mcp_server.handle(request)
            if response
              $stdout.puts(MCP::Protocol.encode(response))
              $stdout.flush
            end
          rescue MCP::Protocol::ParseError => e
            err = MCP::Protocol.error_response(id: nil, code: -32700, message: e.message)
            $stdout.puts(MCP::Protocol.encode(err))
            $stdout.flush
          end
        end
      end

      desc "worker", "Start background job worker"
      option :concurrency, aliases: "-c", type: :numeric, default: 2
      def worker
        app_file = File.join(Dir.pwd, "app.rb")
        unless File.exist?(app_file)
          puts "Error: app.rb not found"
          exit 1
        end
        require app_file
        whoosh_app = ObjectSpace.each_object(Whoosh::App).first
        unless whoosh_app
          puts "Error: No Whoosh::App found"
          exit 1
        end

        whoosh_app.to_rack  # boots everything including Jobs
        concurrency = options[:concurrency]
        puts "=> Whoosh worker (#{concurrency} threads)..."

        workers = concurrency.times.map do
          w = Jobs::Worker.new(backend: Jobs.backend, di: Jobs.di,
            max_retries: whoosh_app.config.data.dig("jobs", "retry") || 3,
            retry_delay: whoosh_app.config.data.dig("jobs", "retry_delay") || 5)
          Thread.new { w.run_loop }
          w
        end

        trap("INT") { workers.each(&:stop); exit 0 }
        trap("TERM") { workers.each(&:stop); exit 0 }
        sleep
      end

      desc "db SUBCOMMAND", "Database commands"
      subcommand "db", Class.new(Thor) {
        namespace "db"

        desc "migrate", "Run pending migrations"
        def migrate
          require_app!
          db = find_db
          Sequel::Migrator.run(db, "db/migrations")
          puts "Migrations complete."
        end

        desc "rollback", "Rollback last migration"
        def rollback
          require_app!
          db = find_db
          Sequel::Migrator.run(db, "db/migrations", target: 0)
          puts "Rollback complete."
        end

        desc "status", "Show migration status"
        def status
          puts "Migration files in db/migrations/:"
          Dir.glob("db/migrations/*.rb").sort.each { |f| puts "  #{File.basename(f)}" }
        end

        private

        def require_app!
          require File.join(Dir.pwd, "app") if File.exist?(File.join(Dir.pwd, "app.rb"))
        end

        def find_db
          require "sequel"
          url = ENV["DATABASE_URL"] || "sqlite://db/development.sqlite3"
          Sequel.connect(url)
        end
      }

      desc "ci", "Run full CI pipeline (lint + security + audit + tests + coverage)"
      def ci
        puts "=> Whoosh CI Pipeline"
        puts "=" * 50
        puts ""

        steps = []
        skipped = []

        # Step 1: Rubocop (lint)
        if system("bundle exec rubocop --version > /dev/null 2>&1")
          steps << { name: "Rubocop (lint)", cmd: "bundle exec rubocop --format simple" }
        else
          skipped << "Rubocop (add rubocop to Gemfile)"
        end

        # Step 2: Brakeman (security scan)
        if system("bundle exec brakeman --version > /dev/null 2>&1")
          steps << { name: "Brakeman (security)", cmd: "bundle exec brakeman -q --no-pager" }
        else
          skipped << "Brakeman (add brakeman to Gemfile)"
        end

        # Step 3: Bundle audit (CVE check)
        if system("bundle exec bundle-audit version > /dev/null 2>&1")
          steps << { name: "Bundle Audit (CVE)", cmd: "bundle exec bundle-audit check --update" }
        elsif system("bundle audit --help > /dev/null 2>&1")
          steps << { name: "Bundle Audit (CVE)", cmd: "bundle audit" }
        else
          skipped << "Bundle Audit (add bundler-audit to Gemfile)"
        end

        # Step 4: Secret leak scan (built-in, no gem needed)
        steps << { name: "Secret Scan", type: :secret_scan }

        # Step 5: RSpec (tests)
        if system("bundle exec rspec --version > /dev/null 2>&1")
          steps << { name: "RSpec (tests)", cmd: "bundle exec rspec --format progress" }
        else
          skipped << "RSpec (add rspec to Gemfile)"
        end

        # Step 6: Coverage check (built-in)
        steps << { name: "Coverage Check", type: :coverage_check }

        skipped.each { |s| puts "  [skip] #{s}" }
        puts "" unless skipped.empty?

        failed = []
        steps.each_with_index do |step, i|
          puts "--- [#{i + 1}/#{steps.length}] #{step[:name]} ---"

          success = case step[:type]
          when :secret_scan
            run_secret_scan
          when :coverage_check
            run_coverage_check
          else
            system(step[:cmd])
          end

          if success
            puts "  ✓ #{step[:name]} passed"
          else
            puts "  ✗ #{step[:name]} FAILED"
            failed << step[:name]
          end
          puts ""
        end

        puts "=" * 50
        if failed.empty?
          puts "=> All #{steps.length} checks passed! ✓"
          exit 0
        else
          puts "=> FAILED: #{failed.join(', ')}"
          exit 1
        end
      end

      private

      def run_secret_scan
        patterns = [
          /(?:api[_-]?key|secret|password|token)\s*[:=]\s*["'][A-Za-z0-9+\/=]{8,}["']/i,
          /(?:sk-|pk-|rk-)[a-zA-Z0-9]{20,}/,
          /-----BEGIN (?:RSA |EC )?PRIVATE KEY-----/,
          /AKIA[0-9A-Z]{16}/,  # AWS access key
        ]

        leaked = []
        Dir.glob("{app.rb,lib/**/*.rb,endpoints/**/*.rb,config/**/*.rb}").each do |file|
          next if file.include?("spec/") || file.include?("test/")
          content = File.read(file) rescue next
          patterns.each do |pattern|
            content.each_line.with_index do |line, i|
              if line.match?(pattern) && !line.include?("ENV[") && !line.include?("ENV.fetch")
                leaked << "#{file}:#{i + 1}: #{line.strip[0..80]}"
              end
            end
          end
        end

        if leaked.empty?
          true
        else
          puts "  Potential secrets found:"
          leaked.each { |l| puts "    #{l}" }
          false
        end
      end

      def run_coverage_check
        coverage_file = File.join(Dir.pwd, "coverage", ".last_run.json")
        unless File.exist?(coverage_file)
          puts "  [info] No coverage data found (add simplecov to test_helper for tracking)"
          true  # Don't fail if SimpleCov not set up
        else
          require "json"
          data = JSON.parse(File.read(coverage_file))
          coverage = data.dig("result", "line") || data.dig("result", "covered_percent") || 0
          threshold = 80

          if coverage >= threshold
            puts "  Coverage: #{coverage.round(1)}% (threshold: #{threshold}%)"
            true
          else
            puts "  Coverage: #{coverage.round(1)}% — below #{threshold}% threshold"
            false
          end
        end
      end

      public

      desc "new NAME", "Create a new Whoosh project"
      option :minimal, type: :boolean, default: false
      option :full, type: :boolean, default: false
      def new(name)
        require "whoosh/cli/project_generator"
        ProjectGenerator.create(name, minimal: options[:minimal], full: options[:full])
      end

      desc "generate SUBCOMMAND", "Generate components"
      subcommand "generate", Class.new(Thor) {
        namespace "generate"

        desc "endpoint NAME [FIELDS...]", "Generate endpoint with schema and test"
        def endpoint(name, *fields)
          require "whoosh/cli/generators"
          Whoosh::CLI::Generators.endpoint(name, fields)
        end

        desc "schema NAME [FIELDS...]", "Generate a schema file"
        def schema(name, *fields)
          require "whoosh/cli/generators"
          Whoosh::CLI::Generators.schema(name, fields)
        end

        desc "model NAME [FIELDS...]", "Generate model with migration"
        def model(name, *fields)
          require "whoosh/cli/generators"
          Whoosh::CLI::Generators.model(name, fields)
        end

        desc "migration NAME", "Generate blank migration"
        def migration(name)
          require "whoosh/cli/generators"
          Whoosh::CLI::Generators.migration(name)
        end

        desc "plugin NAME", "Generate plugin boilerplate"
        def plugin(name)
          require "whoosh/cli/generators"
          Whoosh::CLI::Generators.plugin(name)
        end

        desc "proto NAME", "Generate .proto file"
        def proto(name)
          require "whoosh/cli/generators"
          Whoosh::CLI::Generators.proto(name)
        end
      }
    end
  end
end
