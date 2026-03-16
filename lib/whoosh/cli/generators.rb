# lib/whoosh/cli/generators.rb
# frozen_string_literal: true

require "fileutils"

module Whoosh
  module CLI
    class Generators
      TYPE_MAP = {
        "string" => "String", "integer" => "Integer", "float" => "Float",
        "boolean" => "Whoosh::Types::Bool", "text" => "String",
        "datetime" => "Time"
      }.freeze

      def self.endpoint(name, fields = [], root: Dir.pwd)
        cn = classify(name)
        FileUtils.mkdir_p(File.join(root, "endpoints"))
        FileUtils.mkdir_p(File.join(root, "schemas"))
        FileUtils.mkdir_p(File.join(root, "test", "endpoints"))

        # Generate schema with fields
        schema(name, fields, root: root) unless fields.empty?

        unless fields.empty?
          # schema already generated above, skip the blank one
        else
          File.write(File.join(root, "schemas", "#{name}.rb"),
            "# frozen_string_literal: true\n\nclass #{cn}Request < Whoosh::Schema\n  # Add fields here\nend\n\nclass #{cn}Response < Whoosh::Schema\n  # Add fields here\nend\n")
        end

        File.write(File.join(root, "endpoints", "#{name}.rb"),
          "# frozen_string_literal: true\n\nclass #{cn}Endpoint < Whoosh::Endpoint\n  post \"/#{name}\", request: #{cn}Request\n\n  def call(req)\n    { message: \"#{cn} endpoint\" }\n  end\nend\n")

        File.write(File.join(root, "test", "endpoints", "#{name}_test.rb"),
          "# frozen_string_literal: true\n\nrequire \"test_helper\"\n\nRSpec.describe #{cn}Endpoint do\n  it \"responds to POST /#{name}\" do\n    post \"/#{name}\"\n    expect(last_response.status).to eq(200)\n  end\nend\n")

        puts "Created endpoints/#{name}.rb, schemas/#{name}.rb, test/endpoints/#{name}_test.rb"
      end

      def self.schema(name, fields = [], root: Dir.pwd)
        cn = classify(name)
        FileUtils.mkdir_p(File.join(root, "schemas"))

        field_lines = fields.map { |f|
          col, type = f.split(":")
          ruby_type = TYPE_MAP[type] || "String"
          "  field :#{col}, #{ruby_type}, required: true"
        }.join("\n")
        field_lines = "  # field :name, String, required: true, desc: \"Description\"" if field_lines.empty?

        File.write(File.join(root, "schemas", "#{name}.rb"),
          "# frozen_string_literal: true\n\nclass #{cn}Schema < Whoosh::Schema\n#{field_lines}\nend\n")
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

        FileUtils.mkdir_p(File.join(root, "test", "models"))
        File.write(File.join(root, "test", "models", "#{name.downcase}_test.rb"),
          "# frozen_string_literal: true\n\nrequire \"test_helper\"\n\nRSpec.describe #{cn} do\n  it \"exists\" do\n    expect(#{cn}).to be_a(Class)\n  end\nend\n")

        puts "Created models/#{name.downcase}.rb, db/migrations/#{ts}_create_#{table}.rb"
      end

      def self.migration(name, root: Dir.pwd)
        ts = Time.now.strftime("%Y%m%d%H%M%S")
        FileUtils.mkdir_p(File.join(root, "db", "migrations"))
        File.write(File.join(root, "db", "migrations", "#{ts}_#{name}.rb"),
          "Sequel.migration do\n  change do\n    # Add migration code here\n  end\nend\n")
        puts "Created db/migrations/#{ts}_#{name}.rb"
      end

      def self.plugin(name, root: Dir.pwd)
        cn = classify(name)
        FileUtils.mkdir_p(File.join(root, "lib"))

        File.write(File.join(root, "lib", "#{name}_plugin.rb"), <<~RUBY)
          # frozen_string_literal: true

          class #{cn}Plugin < Whoosh::Plugins::Base
            gem_name "#{name}"
            accessor_name :#{name.tr("-", "_")}

            def self.initialize_plugin(config)
              # Initialize and return plugin instance
              nil
            end
          end
        RUBY
        puts "Created lib/#{name}_plugin.rb"
      end

      def self.proto(name, root: Dir.pwd)
        FileUtils.mkdir_p(File.join(root, "protos"))
        msg_name = name.match?(/[_-]/) ? classify(name) : name

        File.write(File.join(root, "protos", "#{name.downcase}.proto"), <<~PROTO)
          syntax = "proto3";

          package whoosh;

          message #{msg_name} {
            // Add fields here
            // string name = 1;
          }
        PROTO
        puts "Created protos/#{name.downcase}.proto"
      end

      def self.classify(name)
        name.split(/[-_]/).map(&:capitalize).join
      end
    end
  end
end
