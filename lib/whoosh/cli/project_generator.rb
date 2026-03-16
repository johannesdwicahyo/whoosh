# lib/whoosh/cli/project_generator.rb
# frozen_string_literal: true

require "fileutils"

module Whoosh
  module CLI
    class ProjectGenerator
      def self.create(name, root: Dir.pwd, minimal: false, full: false)
        dir = File.join(root, name)
        FileUtils.mkdir_p(dir)
        %w[config endpoints schemas models middleware db/migrations test/endpoints].each do |d|
          FileUtils.mkdir_p(File.join(dir, d))
        end

        write(dir, "app.rb", app_rb(name))
        write(dir, "config.ru", config_ru)
        write(dir, "Gemfile", gemfile(full: full))
        write(dir, "Rakefile", "require \"rspec/core/rake_task\"\nRSpec::Core::RakeTask.new(:spec)\ntask default: :spec\n")
        write(dir, "config/app.yml", app_yml(name))
        write(dir, "endpoints/health.rb", health_endpoint)
        write(dir, "schemas/health.rb", health_schema)
        write(dir, "test/test_helper.rb", test_helper)
        write(dir, ".env.example", "# WHOOSH_PORT=9292\n# WHOOSH_ENV=development\n# DATABASE_URL=sqlite://db/development.sqlite3\n")
        puts "Created #{name}/ — run `cd #{name} && bundle install && whoosh server`"
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

            App = Whoosh::App.new

            App.openapi do
              title "#{name.capitalize} API"
              version "0.1.0"
            end

            App.load_endpoints(File.join(__dir__, "endpoints"))
          RUBY
        end

        def config_ru
          "# frozen_string_literal: true\n\nrequire_relative \"app\"\n\nrun App.to_rack\n"
        end

        def gemfile(full: false)
          g = "source \"https://rubygems.org\"\n\ngem \"whoosh\"\n"
          if full
            g += "\n# AI & NLP\ngem \"ruby_llm\"\ngem \"lingua-ruby\"\ngem \"ner-ruby\"\n\n# Database\ngem \"sequel\"\ngem \"sqlite3\"\n"
          end
          g += "\ngroup :development, :test do\n  gem \"rspec\"\n  gem \"rack-test\"\nend\n"
        end

        def app_yml(name)
          "app:\n  name: \"#{name.capitalize} API\"\n  port: 9292\n  host: localhost\n\nlogging:\n  level: info\n  format: json\n\ndocs:\n  enabled: true\n"
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
          "# frozen_string_literal: true\n\nclass HealthResponse < Whoosh::Schema\n  field :status, String, required: true, desc: \"Health status\"\n  field :version, String, desc: \"API version\"\nend\n"
        end

        def test_helper
          "# frozen_string_literal: true\n\nrequire \"rack/test\"\nrequire_relative \"../app\"\n\nRSpec.configure do |config|\n  config.include Rack::Test::Methods\nend\n"
        end
      end
    end
  end
end
