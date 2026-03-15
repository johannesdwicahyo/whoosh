# frozen_string_literal: true

require "spec_helper"

class TestHealthEndpoint < Whoosh::Endpoint
  get "/health"

  def call(req)
    { status: "ok" }
  end
end

class TestChatEndpoint < Whoosh::Endpoint
  post "/chat", mcp: true

  def call(req)
    { reply: "hello" }
  end
end

class TestMultiEndpoint < Whoosh::Endpoint
  get "/items"
  post "/items"

  def call(req)
    { method: req.method }
  end
end

RSpec.describe Whoosh::Endpoint do
  describe ".declared_routes" do
    it "returns routes declared via DSL" do
      routes = TestHealthEndpoint.declared_routes
      expect(routes.length).to eq(1)
      expect(routes.first[:method]).to eq("GET")
      expect(routes.first[:path]).to eq("/health")
    end

    it "stores metadata" do
      routes = TestChatEndpoint.declared_routes
      expect(routes.first[:metadata][:mcp]).to be true
    end

    it "supports multiple routes per endpoint" do
      routes = TestMultiEndpoint.declared_routes
      expect(routes.length).to eq(2)
      expect(routes.map { |r| r[:method] }).to contain_exactly("GET", "POST")
    end
  end

  describe "route DSL" do
    it "supports all HTTP verbs" do
      endpoint_class = Class.new(Whoosh::Endpoint) do
        get "/a"
        post "/b"
        put "/c"
        patch "/d"
        delete "/e"
        options "/f"
      end

      methods = endpoint_class.declared_routes.map { |r| r[:method] }
      expect(methods).to contain_exactly("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
    end

    it "stores request and response schemas" do
      schema_class = Class.new(Whoosh::Schema) do
        field :name, String, required: true
      end

      endpoint_class = Class.new(Whoosh::Endpoint) do
        post "/test", request: schema_class, response: schema_class
      end

      route = endpoint_class.declared_routes.first
      expect(route[:request_schema]).to eq(schema_class)
      expect(route[:response_schema]).to eq(schema_class)
    end
  end

  describe "Endpoint::Context" do
    it "delegates unknown methods to the app" do
      fake_app = Object.new
      def fake_app.llm; "llm_instance"; end

      context = Whoosh::Endpoint::Context.new(fake_app, nil)
      expect(context.llm).to eq("llm_instance")
    end

    it "provides access to the request" do
      context = Whoosh::Endpoint::Context.new(nil, "the_request")
      expect(context.request).to eq("the_request")
    end
  end
end
