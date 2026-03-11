# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Serialization::Negotiator do
  describe ".for_accept" do
    it "returns JSON serializer for application/json" do
      serializer = Whoosh::Serialization::Negotiator.for_accept("application/json")
      expect(serializer).to eq(Whoosh::Serialization::Json)
    end

    it "returns JSON serializer for */*" do
      serializer = Whoosh::Serialization::Negotiator.for_accept("*/*")
      expect(serializer).to eq(Whoosh::Serialization::Json)
    end

    it "returns JSON serializer when no Accept header" do
      serializer = Whoosh::Serialization::Negotiator.for_accept(nil)
      expect(serializer).to eq(Whoosh::Serialization::Json)
    end
  end

  describe ".for_content_type" do
    it "returns JSON deserializer for application/json" do
      deserializer = Whoosh::Serialization::Negotiator.for_content_type("application/json")
      expect(deserializer).to eq(Whoosh::Serialization::Json)
    end

    it "defaults to JSON for unknown types" do
      deserializer = Whoosh::Serialization::Negotiator.for_content_type("text/plain")
      expect(deserializer).to eq(Whoosh::Serialization::Json)
    end
  end
end
