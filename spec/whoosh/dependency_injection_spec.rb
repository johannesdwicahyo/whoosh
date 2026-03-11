# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::DependencyInjection do
  let(:di) { Whoosh::DependencyInjection.new }

  describe "#provide (singleton)" do
    it "registers and resolves a singleton dependency" do
      call_count = 0
      di.provide(:db) { call_count += 1; "connection" }

      expect(di.resolve(:db)).to eq("connection")
      expect(di.resolve(:db)).to eq("connection")
      expect(call_count).to eq(1) # Only called once
    end
  end

  describe "#provide (request scope)" do
    it "registers a request-scoped dependency" do
      call_count = 0
      di.provide(:current_user, scope: :request) { |req| call_count += 1; "user_#{req}" }

      expect(di.resolve(:current_user, request: "req1")).to eq("user_req1")
      expect(di.resolve(:current_user, request: "req2")).to eq("user_req2")
      expect(call_count).to eq(2) # Called each time
    end
  end

  describe "dependency chains" do
    it "resolves dependencies that depend on other dependencies" do
      di.provide(:config) { { host: "localhost" } }
      di.provide(:db) { |config:| "db://#{config[:host]}" }

      expect(di.resolve(:db)).to eq("db://localhost")
    end
  end

  describe "circular dependency detection" do
    it "raises DependencyError on circular deps at boot via validate!" do
      di.provide(:a) { |b:| b }
      di.provide(:b) { |a:| a }

      expect { di.validate! }.to raise_error(Whoosh::Errors::DependencyError, /circular/i)
    end

    it "also raises at runtime if resolve is called without validate!" do
      di.provide(:a) { |b:| b }
      di.provide(:b) { |a:| a }

      expect { di.resolve(:a) }.to raise_error(Whoosh::Errors::DependencyError, /circular/i)
    end
  end

  describe "#validate!" do
    it "succeeds for valid dependency graph" do
      di.provide(:config) { { host: "localhost" } }
      di.provide(:db) { |config:| "db://#{config[:host]}" }

      expect { di.validate! }.not_to raise_error
    end

    it "raises for unknown dependency references" do
      di.provide(:db) { |config:| "db://#{config[:host]}" }

      expect { di.validate! }.to raise_error(Whoosh::Errors::DependencyError, /unknown.*config/i)
    end
  end

  describe "#close_all" do
    it "calls close on singletons that respond to it" do
      closeable = double("closeable", close: nil)
      di.provide(:conn) { closeable }
      di.resolve(:conn) # Initialize it

      expect(closeable).to receive(:close)
      di.close_all
    end
  end

  describe "#inject_for" do
    it "returns hash of resolved dependencies for given keyword names" do
      di.provide(:db) { "connection" }
      di.provide(:cache) { "redis" }

      result = di.inject_for([:db, :cache])
      expect(result).to eq({ db: "connection", cache: "redis" })
    end

    it "returns empty hash for empty list" do
      expect(di.inject_for([])).to eq({})
    end
  end

  describe "override" do
    it "allows app.provide to override plugins" do
      di.provide(:db) { "original" }
      di.provide(:db) { "overridden" }

      expect(di.resolve(:db)).to eq("overridden")
    end
  end
end
