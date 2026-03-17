# spec/whoosh/cli/project_generator_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh/cli/project_generator"
require "tmpdir"

RSpec.describe Whoosh::CLI::ProjectGenerator do
  describe ".create" do
    it "creates project directory structure" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        project = File.join(dir, "myapp")
        expect(File.directory?(project)).to be true
        expect(File.exist?(File.join(project, "app.rb"))).to be true
        expect(File.exist?(File.join(project, "config.ru"))).to be true
        expect(File.exist?(File.join(project, "Gemfile"))).to be true
        expect(File.exist?(File.join(project, "config", "app.yml"))).to be true
        expect(File.directory?(File.join(project, "endpoints"))).to be true
        expect(File.directory?(File.join(project, "schemas"))).to be true
        expect(File.directory?(File.join(project, "db", "migrations"))).to be true
      end
    end

    it "generates valid app.rb" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        content = File.read(File.join(dir, "myapp", "app.rb"))
        expect(content).to include("Whoosh::App.new")
        expect(content).to include("require \"whoosh\"")
      end
    end

    it "generates valid config.ru" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        content = File.read(File.join(dir, "myapp", "config.ru"))
        expect(content).to include("run")
        expect(content).to include("to_rack")
      end
    end

    it "generates a health endpoint" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        content = File.read(File.join(dir, "myapp", "endpoints", "health.rb"))
        expect(content).to include("Whoosh::Endpoint")
        expect(content).to include("/health")
      end
    end

    it "generates Gemfile with whoosh" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        content = File.read(File.join(dir, "myapp", "Gemfile"))
        expect(content).to include("whoosh")
      end
    end

    it "generates plugins.yml" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        expect(File.exist?(File.join(dir, "myapp", "config", "plugins.yml"))).to be true
      end
    end

    it "generates Dockerfile" do
      Dir.mktmpdir do |dir|
        Whoosh::CLI::ProjectGenerator.create("myapp", root: dir)
        expect(File.exist?(File.join(dir, "myapp", "Dockerfile"))).to be true
        content = File.read(File.join(dir, "myapp", "Dockerfile"))
        expect(content).to include("ruby:3.4")
        expect(content).to include("whoosh")
      end
    end
  end
end
