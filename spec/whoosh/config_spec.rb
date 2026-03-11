# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Whoosh::Config do
  describe ".load" do
    it "returns defaults when no config file exists" do
      config = Whoosh::Config.load(root: "/nonexistent")
      expect(config.port).to eq(9292)
      expect(config.host).to eq("localhost")
      expect(config.env).to eq("development")
    end

    it "loads from YAML file" do
      Dir.mktmpdir do |dir|
        config_dir = File.join(dir, "config")
        Dir.mkdir(config_dir)
        File.write(File.join(config_dir, "app.yml"), <<~YAML)
          app:
            name: "Test API"
            port: 3000
        YAML

        config = Whoosh::Config.load(root: dir)
        expect(config.port).to eq(3000)
        expect(config.app_name).to eq("Test API")
      end
    end

    it "environment variables take precedence" do
      Dir.mktmpdir do |dir|
        config_dir = File.join(dir, "config")
        Dir.mkdir(config_dir)
        File.write(File.join(config_dir, "app.yml"), <<~YAML)
          app:
            port: 3000
        YAML

        ENV["WHOOSH_PORT"] = "4000"
        config = Whoosh::Config.load(root: dir)
        expect(config.port).to eq(4000)
      ensure
        ENV.delete("WHOOSH_PORT")
      end
    end
  end

  describe "DSL overrides" do
    it "allows setting values" do
      config = Whoosh::Config.load(root: "/nonexistent")
      config.port = 5000
      expect(config.port).to eq(5000)
    end
  end

  describe "json_engine" do
    it "defaults to :json" do
      config = Whoosh::Config.load(root: "/nonexistent")
      expect(config.json_engine).to eq(:json)
    end
  end
end
