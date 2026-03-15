# frozen_string_literal: true

require "spec_helper"
require "rack/test"

# Test schema for validated endpoints
class GreetRequest < Whoosh::Schema
  field :name, String, required: true, desc: "Name to greet"
  field :greeting, String, default: "Hello"
end

RSpec.describe Whoosh::App do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "basic routing" do
    before do
      application.get "/health" do
        { status: "ok" }
      end
    end

    it "handles GET requests" do
      get "/health"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)).to eq({ "status" => "ok" })
    end

    it "returns 404 for unknown routes" do
      get "/missing"
      expect(last_response.status).to eq(404)
      expect(JSON.parse(last_response.body)["error"]).to eq("not_found")
    end

    it "sets JSON content-type" do
      get "/health"
      expect(last_response.content_type).to include("application/json")
    end
  end

  describe "HTTP methods" do
    before do
      application.get("/get")    { { method: "get" } }
      application.post("/post")  { { method: "post" } }
      application.put("/put")    { { method: "put" } }
      application.patch("/patch") { { method: "patch" } }
      application.delete("/del") { { method: "delete" } }
    end

    it "routes GET" do
      get "/get"
      expect(JSON.parse(last_response.body)["method"]).to eq("get")
    end

    it "routes POST" do
      post "/post"
      expect(JSON.parse(last_response.body)["method"]).to eq("post")
    end

    it "routes PUT" do
      put "/put"
      expect(JSON.parse(last_response.body)["method"]).to eq("put")
    end

    it "routes PATCH" do
      patch "/patch"
      expect(JSON.parse(last_response.body)["method"]).to eq("patch")
    end

    it "routes DELETE" do
      delete "/del"
      expect(JSON.parse(last_response.body)["method"]).to eq("delete")
    end
  end

  describe "path params" do
    before do
      application.get "/users/:id" do |req|
        { user_id: req.params[:id] }
      end
    end

    it "extracts path params" do
      get "/users/42"
      expect(JSON.parse(last_response.body)["user_id"]).to eq("42")
    end
  end

  describe "schema validation" do
    before do
      application.post "/greet", request: GreetRequest do |req|
        { message: "#{req.body[:greeting]}, #{req.body[:name]}!" }
      end
    end

    it "validates and processes valid input" do
      post "/greet", { name: "Alice" }.to_json, "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["message"]).to eq("Hello, Alice!")
    end

    it "returns 422 for invalid input" do
      post "/greet", {}.to_json, "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(422)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("validation_failed")
    end
  end

  describe "route groups" do
    before do
      application.group "/api/v1" do
        get "/items" do
          { items: [] }
        end

        post "/items" do |req|
          { created: true }
        end
      end
    end

    it "prefixes routes" do
      get "/api/v1/items"
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["items"]).to eq([])
    end

    it "handles POST in groups" do
      post "/api/v1/items"
      expect(last_response.status).to eq(200)
    end
  end

  describe "dependency injection" do
    before do
      application.provide(:greeting) { "Howdy" }

      application.get "/hello/:name" do |req, greeting:|
        { message: "#{greeting}, #{req.params[:name]}!" }
      end
    end

    it "injects dependencies into handlers" do
      get "/hello/Bob"
      expect(JSON.parse(last_response.body)["message"]).to eq("Howdy, Bob!")
    end
  end

  describe "error handling" do
    before do
      application.get "/explode" do
        raise "boom!"
      end

      application.on_error do |error, req|
        { error: "caught", message: error.message }
      end
    end

    it "catches errors and returns JSON" do
      get "/explode"
      expect(last_response.status).to eq(500)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("caught")
      expect(body["message"]).to eq("boom!")
    end
  end

  describe "security headers" do
    before do
      application.get("/test") { { ok: true } }
    end

    it "includes security headers" do
      get "/test"
      expect(last_response.headers["x-content-type-options"]).to eq("nosniff")
      expect(last_response.headers["x-frame-options"]).to eq("DENY")
    end
  end

  describe "#routes" do
    it "lists all registered routes" do
      application.get("/a") { {} }
      application.post("/b") { {} }

      routes = application.routes
      expect(routes.length).to eq(2)
    end
  end
end
