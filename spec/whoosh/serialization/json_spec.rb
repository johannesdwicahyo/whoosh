# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Serialization::Json do
  describe ".encode" do
    it "encodes hash to JSON string" do
      result = Whoosh::Serialization::Json.encode({ name: "test", count: 42 })
      parsed = JSON.parse(result)
      expect(parsed["name"]).to eq("test")
      expect(parsed["count"]).to eq(42)
    end

    it "handles Time as ISO 8601" do
      time = Time.utc(2026, 3, 11, 10, 30, 0)
      result = Whoosh::Serialization::Json.encode({ created_at: time })
      parsed = JSON.parse(result)
      expect(parsed["created_at"]).to eq("2026-03-11T10:30:00Z")
    end
  end

  describe ".decode" do
    it "decodes JSON string to hash" do
      result = Whoosh::Serialization::Json.decode('{"name":"test"}')
      expect(result).to eq({ "name" => "test" })
    end

    it "returns nil for nil input" do
      expect(Whoosh::Serialization::Json.decode(nil)).to be_nil
    end
  end
end
