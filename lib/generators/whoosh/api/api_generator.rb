require "rails/generators"
require_relative "fields"

module Whoosh
  module Generators
    # bin/rails g whoosh:api Orders
    # Writes a list and a show endpoint, a schema from the model's columns and a test,
    # and adds the class to the mount line in config/routes.rb.
    class ApiGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      def create_files
        template "api.rb.tt", "app/api/#{resource}_api.rb"
        template "schema.rb.tt", "app/schemas/#{record}_schema.rb"
        if File.directory?(File.join(destination_root, "spec"))
          template "spec.rb.tt", "spec/requests/#{resource}_api_spec.rb"
        else
          template "test.rb.tt", "test/integration/#{resource}_api_test.rb"
        end
      end

      def add_to_mount
        routes = File.join(destination_root, "config/routes.rb")
        mount = /Whoosh\.app\(([^)]*)\)/
        if File.exist?(routes) && File.read(routes).match?(mount)
          gsub_file "config/routes.rb", mount do |line|
            line.include?(%("#{api_class}")) ? line : line.sub(/\)\z/, %(, "#{api_class}"\)))
          end
        else
          say %(Add "#{api_class}" to your mount line: mount Whoosh.app("#{api_class}"), at: "/api"), :yellow
        end
      end

      private

      def resource = file_name.pluralize
      def record = file_name.singularize
      def api_class = "#{resource.camelize}Api"
      def schema_class = "#{record.camelize}Schema"
      def model_class = record.camelize
      def test_user = "Object.new" # authorize accepts anyone signed in until you narrow it

      def fields
        @fields ||= begin
          model = model_class.safe_constantize
          if model.respond_to?(:columns) && model.table_exists?
            Fields.from(model.columns, enums: model.respond_to?(:defined_enums) ? model.defined_enums.keys : [])
          else
            [["field :id, :integer"], []]
          end
        end
      end

      # Where the API answers, read from the app: "/api" from the mount line, "/v1" from ApplicationApi.
      def url
        routes = File.join(destination_root, "config/routes.rb")
        base = File.join(destination_root, "app/api/application_api.rb")
        at = File.exist?(routes) && File.read(routes)[/Whoosh\.app\(.*?\),\s*at:\s*["']([^"']+)/, 1]
        version = File.exist?(base) && File.read(base)[/^\s*version\s+(\d+)/, 1]
        "#{at || '/api'}#{"/v#{version}" if version}/#{resource}"
      end
    end
  end
end
