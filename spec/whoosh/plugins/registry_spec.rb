# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Plugins::Registry do
  let(:registry) { Whoosh::Plugins::Registry.new }

  describe "#register" do
    it "registers a gem with an accessor name" do
      registry.register("lingua-ruby", accessor: :lingua)
      expect(registry.registered?("lingua-ruby")).to be true
    end

    it "stores the accessor name" do
      registry.register("lingua-ruby", accessor: :lingua)
      expect(registry.accessor_for("lingua-ruby")).to eq(:lingua)
    end
  end

  describe "#scan_gemfile_lock" do
    it "detects known gems from a Gemfile.lock string" do
      lock_content = <<~LOCK
        GEM
          remote: https://rubygems.org/
          specs:
            lingua-ruby (0.1.0)
            rack (3.0.0)
            ner-ruby (0.2.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          lingua-ruby
          ner-ruby
          rack
      LOCK

      detected = registry.scan_gemfile_lock(lock_content)
      expect(detected).to include("lingua-ruby")
      expect(detected).to include("ner-ruby")
      expect(detected).not_to include("rack")
    end

    it "returns empty array when no known gems found" do
      lock_content = <<~LOCK
        GEM
          remote: https://rubygems.org/
          specs:
            rack (3.0.0)

        DEPENDENCIES
          rack
      LOCK

      detected = registry.scan_gemfile_lock(lock_content)
      expect(detected).to be_empty
    end
  end

  describe "#define_accessors" do
    it "defines lazy-loaded methods on the target object" do
      registry.register("json", accessor: :json_plugin, initializer: -> (_config) { { loaded: true } })

      target = Object.new
      registry.define_accessors(target)

      expect(target).to respond_to(:json_plugin)
    end

    it "lazy-loads the plugin on first access" do
      call_count = 0
      registry.register("json", accessor: :test_plugin, initializer: -> (_config) {
        call_count += 1
        "plugin_instance"
      })

      target = Object.new
      registry.define_accessors(target)

      expect(call_count).to eq(0)
      result = target.test_plugin
      expect(result).to eq("plugin_instance")
      expect(call_count).to eq(1)

      # Second call returns cached value
      target.test_plugin
      expect(call_count).to eq(1)
    end
  end

  describe "#configure" do
    it "stores plugin configuration" do
      registry.register("lingua-ruby", accessor: :lingua)
      registry.configure(:lingua, { languages: [:en, :id] })
      expect(registry.config_for(:lingua)).to eq({ languages: [:en, :id] })
    end
  end

  describe "#disable" do
    it "marks a plugin as disabled" do
      registry.register("lingua-ruby", accessor: :lingua)
      registry.disable(:lingua)
      expect(registry.disabled?(:lingua)).to be true
    end
  end

  describe "default gem mappings" do
    it "has built-in mappings for ecosystem gems" do
      expect(registry.accessor_for("lingua-ruby")).to eq(:lingua)
      expect(registry.accessor_for("ner-ruby")).to eq(:ner)
      expect(registry.accessor_for("ruby_llm")).to eq(:llm)
      expect(registry.accessor_for("keyword-ruby")).to eq(:keyword)
      expect(registry.accessor_for("guardrails-ruby")).to eq(:guardrails)
      expect(registry.accessor_for("sequel")).to eq(:db)
    end
  end
end
