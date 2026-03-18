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

      desc "ci", "Run full CI pipeline (lint + security + tests)"
      def ci
        puts "=> Whoosh CI Pipeline"
        puts "=" * 50
        puts ""

        steps = []

        # Step 1: Rubocop (lint)
        if system("bundle exec rubocop --version > /dev/null 2>&1")
          steps << { name: "Rubocop (lint)", cmd: "bundle exec rubocop --format simple" }
        else
          puts "  [skip] Rubocop not installed (add rubocop to Gemfile)"
        end

        # Step 2: Brakeman (security)
        if system("bundle exec brakeman --version > /dev/null 2>&1")
          steps << { name: "Brakeman (security)", cmd: "bundle exec brakeman -q --no-pager" }
        else
          puts "  [skip] Brakeman not installed (add brakeman to Gemfile)"
        end

        # Step 3: RSpec (tests)
        if system("bundle exec rspec --version > /dev/null 2>&1")
          steps << { name: "RSpec (tests)", cmd: "bundle exec rspec --format progress" }
        else
          puts "  [skip] RSpec not installed"
        end

        # Step 4: Gem build check
        gemspec = Dir.glob("*.gemspec").first
        if gemspec
          steps << { name: "Gem build", cmd: "gem build #{gemspec} --quiet" }
        end

        failed = []
        steps.each_with_index do |step, i|
          puts "--- [#{i + 1}/#{steps.length}] #{step[:name]} ---"
          success = system(step[:cmd])
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
          puts "=> All checks passed! ✓"
          exit 0
        else
          puts "=> FAILED: #{failed.join(', ')}"
          exit 1
        end
      end

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
