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
      option :port, aliases: "-p", type: :numeric, default: 9292
      option :host, type: :string, default: "localhost"
      def server
        app_file = File.join(Dir.pwd, "config.ru")
        unless File.exist?(app_file)
          puts "Error: config.ru not found in #{Dir.pwd}"
          exit 1
        end
        puts "Starting Whoosh server on #{options[:host]}:#{options[:port]}..."
        exec("bundle exec rackup #{app_file} -p #{options[:port]} -o #{options[:host]}")
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
