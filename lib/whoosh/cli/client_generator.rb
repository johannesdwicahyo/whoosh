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
