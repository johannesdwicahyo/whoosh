# spec/whoosh/database_integration_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Database integration" do
  describe "Whoosh::Database.connect_from_config" do
    it "returns nil when no database config" do
      expect(Whoosh::Database.connect_from_config({})).to be_nil
    end

    it "returns nil when database has no url" do
      expect(Whoosh::Database.connect_from_config({ "database" => {} })).to be_nil
    end

    it "raises DependencyError if sequel not available" do
      original = Whoosh::Database.instance_variable_get(:@sequel_available)
      Whoosh::Database.instance_variable_set(:@sequel_available, false)
      expect { Whoosh::Database.connect_from_config({ "database" => { "url" => "sqlite://test.db" } }) }.to raise_error(Whoosh::Errors::DependencyError)
      Whoosh::Database.instance_variable_set(:@sequel_available, original)
    end
  end

  describe "App boot" do
    it "does not crash without database config" do
      expect { Whoosh::App.new }.not_to raise_error
    end
  end
end
