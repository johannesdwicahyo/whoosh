# spec/whoosh/env_loader_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Whoosh::EnvLoader do
  describe ".load" do
    it "loads KEY=value pairs into ENV" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".env"), "TEST_WHOOSH_A=hello\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_A"]).to eq("hello")
      ensure
        ENV.delete("TEST_WHOOSH_A")
      end
    end

    it "does not override existing ENV vars" do
      Dir.mktmpdir do |dir|
        ENV["TEST_WHOOSH_B"] = "original"
        File.write(File.join(dir, ".env"), "TEST_WHOOSH_B=overridden\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_B"]).to eq("original")
      ensure
        ENV.delete("TEST_WHOOSH_B")
      end
    end

    it "handles double-quoted values" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".env"), "TEST_WHOOSH_C=\"hello world\"\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_C"]).to eq("hello world")
      ensure
        ENV.delete("TEST_WHOOSH_C")
      end
    end

    it "handles single-quoted values" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".env"), "TEST_WHOOSH_D='single'\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_D"]).to eq("single")
      ensure
        ENV.delete("TEST_WHOOSH_D")
      end
    end

    it "skips comments and blank lines" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".env"), "# comment\n\nTEST_WHOOSH_E=yes\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_E"]).to eq("yes")
      ensure
        ENV.delete("TEST_WHOOSH_E")
      end
    end

    it "handles empty values" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".env"), "TEST_WHOOSH_F=\n")
        Whoosh::EnvLoader.load(dir)
        expect(ENV["TEST_WHOOSH_F"]).to eq("")
      ensure
        ENV.delete("TEST_WHOOSH_F")
      end
    end

    it "does nothing when .env file missing" do
      expect { Whoosh::EnvLoader.load("/nonexistent") }.not_to raise_error
    end
  end
end
