# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Database do
  describe ".config_from" do
    it "extracts database config from app config data" do
      config_data = { "database" => { "url" => "sqlite://db/dev.sqlite3", "max_connections" => 5 } }
      result = Whoosh::Database.config_from(config_data)
      expect(result[:url]).to eq("sqlite://db/dev.sqlite3")
      expect(result[:max_connections]).to eq(5)
    end

    it "returns nil when no database config" do
      expect(Whoosh::Database.config_from({})).to be_nil
    end

    it "returns nil when database has no url" do
      expect(Whoosh::Database.config_from({ "database" => {} })).to be_nil
    end
  end

  describe ".available?" do
    it "returns a boolean" do
      expect(Whoosh::Database.available?).to be(true).or be(false)
    end
  end

  describe ".connect" do
    it "raises DependencyError if sequel gem not available" do
      original = Whoosh::Database.instance_variable_get(:@sequel_available)
      Whoosh::Database.instance_variable_set(:@sequel_available, false)
      expect { Whoosh::Database.connect("sqlite://test.db") }.to raise_error(Whoosh::Errors::DependencyError)
      Whoosh::Database.instance_variable_set(:@sequel_available, original)
    end
  end
end
