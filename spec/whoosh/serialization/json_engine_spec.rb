# spec/whoosh/serialization/json_engine_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "JSON engine selection" do
  describe Whoosh::Serialization::Json do
    it "reports which engine is active" do
      Whoosh::Serialization::Json.detect_engine!
      expect([:json, :oj]).to include(Whoosh::Serialization::Json.engine)
    end

    it "can force stdlib engine" do
      original = Whoosh::Serialization::Json.engine
      Whoosh::Serialization::Json.use_engine(:json)
      expect(Whoosh::Serialization::Json.engine).to eq(:json)
      result = Whoosh::Serialization::Json.encode({ a: 1 })
      expect(JSON.parse(result)["a"]).to eq(1)
      Whoosh::Serialization::Json.use_engine(original || :json)
    end

    it "encodes and decodes correctly regardless of engine" do
      Whoosh::Serialization::Json.detect_engine!
      data = { "name" => "test", "count" => 42 }
      encoded = Whoosh::Serialization::Json.encode(data)
      decoded = Whoosh::Serialization::Json.decode(encoded)
      expect(decoded["name"]).to eq("test")
      expect(decoded["count"]).to eq(42)
    end
  end
end
