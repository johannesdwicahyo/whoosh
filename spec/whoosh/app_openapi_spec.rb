# frozen_string_literal: true

require "spec_helper"
require "rack/test"

class DocsTestSchema < Whoosh::Schema
  field :name, String, required: true, desc: "User name"
end

RSpec.describe "App OpenAPI integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "/openapi.json" do
    before do
      application.post "/users", request: DocsTestSchema do |req|
        { created: true }
      end
      application.get "/health" do
        { status: "ok" }
      end
    end

    it "serves OpenAPI 3.1 spec" do
      get "/openapi.json"
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include("application/json")
      spec = JSON.parse(last_response.body)
      expect(spec["openapi"]).to eq("3.1.0")
    end

    it "includes registered routes" do
      get "/openapi.json"
      spec = JSON.parse(last_response.body)
      expect(spec["paths"]).to have_key("/users")
      expect(spec["paths"]).to have_key("/health")
    end

    it "includes request schemas" do
      get "/openapi.json"
      spec = JSON.parse(last_response.body)
      expect(spec["paths"]["/users"]["post"]["requestBody"]).not_to be_nil
    end
  end

  describe "/docs" do
    before do
      application.get "/health" do
        { status: "ok" }
      end
    end

    it "serves Swagger UI HTML" do
      get "/docs"
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include("text/html")
      expect(last_response.body).to include("swagger-ui")
    end
  end

  describe "openapi DSL" do
    it "configures API metadata" do
      application.openapi do
        title "My API"
        version "2.0.0"
        description "Test API"
      end
      application.get "/test" do
        { ok: true }
      end

      get "/openapi.json"
      spec = JSON.parse(last_response.body)
      expect(spec["info"]["title"]).to eq("My API")
      expect(spec["info"]["version"]).to eq("2.0.0")
    end
  end
end
