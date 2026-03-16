# lib/whoosh/cli/generators.rb
# frozen_string_literal: true

require "fileutils"

module Whoosh
  module CLI
    class Generators
      def self.endpoint(name, root: Dir.pwd)
        cn = classify(name)
        FileUtils.mkdir_p(File.join(root, "endpoints"))
        FileUtils.mkdir_p(File.join(root, "schemas"))
        FileUtils.mkdir_p(File.join(root, "test", "endpoints"))

        File.write(File.join(root, "endpoints", "#{name}.rb"),
          "# frozen_string_literal: true\n\nclass #{cn}Endpoint < Whoosh::Endpoint\n  post \"/#{name}\", request: #{cn}Request\n\n  def call(req)\n    { message: \"#{cn} endpoint\" }\n  end\nend\n")

        File.write(File.join(root, "schemas", "#{name}.rb"),
          "# frozen_string_literal: true\n\nclass #{cn}Request < Whoosh::Schema\n  # Add fields here\nend\n\nclass #{cn}Response < Whoosh::Schema\n  # Add fields here\nend\n")

        File.write(File.join(root, "test", "endpoints", "#{name}_test.rb"),
          "# frozen_string_literal: true\n\nrequire \"test_helper\"\n\nRSpec.describe #{cn}Endpoint do\n  it \"responds to POST /#{name}\" do\n    post \"/#{name}\"\n    expect(last_response.status).to eq(200)\n  end\nend\n")

        puts "Created endpoints/#{name}.rb, schemas/#{name}.rb, test/endpoints/#{name}_test.rb"
      end

      def self.schema(name, root: Dir.pwd)
        cn = classify(name)
        FileUtils.mkdir_p(File.join(root, "schemas"))
        File.write(File.join(root, "schemas", "#{name}.rb"),
          "# frozen_string_literal: true\n\nclass #{cn}Schema < Whoosh::Schema\n  # field :name, String, required: true, desc: \"Description\"\nend\n")
        puts "Created schemas/#{name}.rb"
      end

      def self.model(name, fields = [], root: Dir.pwd)
        cn = classify(name)
        table = "#{name.downcase}s"
        ts = Time.now.strftime("%Y%m%d%H%M%S")

        FileUtils.mkdir_p(File.join(root, "models"))
        FileUtils.mkdir_p(File.join(root, "db", "migrations"))

        File.write(File.join(root, "models", "#{name.downcase}.rb"),
          "# frozen_string_literal: true\n\nclass #{cn} < Sequel::Model(:#{table})\nend\n")

        cols = fields.map { |f|
          col, type = f.split(":")
          st = { "string" => "String", "integer" => "Integer", "float" => "Float", "boolean" => "TrueClass", "text" => "String, text: true", "datetime" => "DateTime" }[type] || "String"
          "      #{st} :#{col}, null: false"
        }.join("\n")

        File.write(File.join(root, "db", "migrations", "#{ts}_create_#{table}.rb"),
          "Sequel.migration do\n  change do\n    create_table(:#{table}) do\n      primary_key :id\n#{cols}\n      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP\n      DateTime :updated_at\n    end\n  end\nend\n")

        puts "Created models/#{name.downcase}.rb, db/migrations/#{ts}_create_#{table}.rb"
      end

      def self.migration(name, root: Dir.pwd)
        ts = Time.now.strftime("%Y%m%d%H%M%S")
        FileUtils.mkdir_p(File.join(root, "db", "migrations"))
        File.write(File.join(root, "db", "migrations", "#{ts}_#{name}.rb"),
          "Sequel.migration do\n  change do\n    # Add migration code here\n  end\nend\n")
        puts "Created db/migrations/#{ts}_#{name}.rb"
      end

      def self.classify(name)
        name.split(/[-_]/).map(&:capitalize).join
      end
    end
  end
end
