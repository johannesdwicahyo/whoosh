require "rails/generators"

module Whoosh
  module Generators
    # bin/rails g whoosh:install [--path=/api]
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      class_option :path, type: :string, default: "/api", desc: "Where to mount the API"

      def create_files
        template "initializer.rb.tt", "config/initializers/whoosh.rb"
        template "application_api.rb.tt", "app/api/application_api.rb"
        template "status_api.rb.tt", "app/api/status_api.rb"
        template "status_schema.rb.tt", "app/schemas/status_schema.rb"
      end

      def mount
        route %(mount Whoosh.app("StatusApi"), at: "#{options[:path]}")
      end

      def next_steps
        say ""
        say "Whoosh is installed.", :green
        say "  1. Set config.authenticate in config/initializers/whoosh.rb"
        say "  2. curl localhost:3000#{options[:path]}/v1/status"
        say "  3. Add API classes in app/api/ and list them in the mount line in config/routes.rb"
      end
    end
  end
end
