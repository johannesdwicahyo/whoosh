# spec/whoosh/cli/generators_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh/cli/generators"
require "tmpdir"

RSpec.describe Whoosh::CLI::Generators do
  describe ".endpoint" do
    it "generates endpoint, schema, and test files" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::Generators.endpoint("chat", root: dir)
        expect(File.exist?(File.join(dir, "endpoints", "chat.rb"))).to be true
        expect(File.exist?(File.join(dir, "schemas", "chat.rb"))).to be true
        expect(File.exist?(File.join(dir, "test", "endpoints", "chat_test.rb"))).to be true
        content = File.read(File.join(dir, "endpoints", "chat.rb"))
        expect(content).to include("ChatEndpoint")
        expect(content).to include("Whoosh::Endpoint")
      end
    end
  end

  describe ".schema" do
    it "generates a schema file" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::Generators.schema("user", root: dir)
        expect(File.exist?(File.join(dir, "schemas", "user.rb"))).to be true
        content = File.read(File.join(dir, "schemas", "user.rb"))
        expect(content).to include("UserSchema")
      end
    end
  end

  describe ".model" do
    it "generates model and migration" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::Generators.model("user", ["name:string", "email:string"], root: dir)
        expect(File.exist?(File.join(dir, "models", "user.rb"))).to be true
        migrations = Dir.glob(File.join(dir, "db", "migrations", "*_create_users.rb"))
        expect(migrations.length).to eq(1)
        expect(File.read(File.join(dir, "models", "user.rb"))).to include("class User")
      end
    end
  end

  describe ".migration" do
    it "generates blank migration" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::Generators.migration("add_age_to_users", root: dir)
        files = Dir.glob(File.join(dir, "db", "migrations", "*_add_age_to_users.rb"))
        expect(files.length).to eq(1)
        expect(File.read(files.first)).to include("Sequel.migration")
      end
    end
  end
end
