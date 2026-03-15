# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::OpenAPI::Generator do
  let(:generator) { Whoosh::OpenAPI::Generator.new(title: "Test API", version: "1.0.0") }

  describe "#add_route" do
    it "adds a route to the spec" do
      generator.add_route(method: "GET", path: "/health")
      spec = generator.generate
      expect(spec[:paths]["/health"][:get]).not_to be_nil
    end

    it "includes request schema" do
      schema_class = Class.new(Whoosh::Schema) { field :name, String, required: true }
      generator.add_route(method: "POST", path: "/users", request_schema: schema_class)
      spec = generator.generate
      expect(spec[:paths]["/users"][:post][:requestBody]).not_to be_nil
    end
  end

  describe "#generate" do
    it "produces valid OpenAPI 3.1 structure" do
      generator.add_route(method: "GET", path: "/health")
      spec = generator.generate
      expect(spec[:openapi]).to eq("3.1.0")
      expect(spec[:info][:title]).to eq("Test API")
    end

    it "converts path params to OpenAPI format" do
      generator.add_route(method: "GET", path: "/users/:id")
      spec = generator.generate
      expect(spec[:paths]["/users/{id}"]).not_to be_nil
      params = spec[:paths]["/users/{id}"][:get][:parameters]
      expect(params.first[:name]).to eq("id")
      expect(params.first[:in]).to eq("path")
    end
  end

  describe "#to_json" do
    it "serializes to JSON" do
      generator.add_route(method: "GET", path: "/health")
      json = generator.to_json
      expect(JSON.parse(json)["openapi"]).to eq("3.1.0")
    end
  end
end
