# frozen_string_literal: true

require "spec_helper"
require "rack"

RSpec.describe Whoosh::Request do
  def build_env(method: "GET", path: "/test", body: nil, headers: {}, content_type: nil)
    opts = { method: method }
    opts[:input] = body if body
    opts["CONTENT_TYPE"] = content_type if content_type
    env = Rack::MockRequest.env_for(path, **opts)
    headers.each do |key, value|
      env["HTTP_#{key.upcase.tr('-', '_')}"] = value
    end
    env
  end

  describe "#method" do
    it "returns the HTTP method" do
      req = Whoosh::Request.new(build_env(method: "POST"))
      expect(req.method).to eq("POST")
    end
  end

  describe "#path" do
    it "returns the request path" do
      req = Whoosh::Request.new(build_env(path: "/api/users"))
      expect(req.path).to eq("/api/users")
    end
  end

  describe "#params" do
    it "returns path params" do
      req = Whoosh::Request.new(build_env)
      req.path_params = { id: "42" }
      expect(req.params[:id]).to eq("42")
    end
  end

  describe "#body" do
    it "parses JSON body" do
      json = '{"name":"test","age":25}'
      req = Whoosh::Request.new(build_env(
        method: "POST",
        body: json,
        content_type: "application/json"
      ))
      expect(req.body).to eq({ "name" => "test", "age" => 25 })
    end

    it "returns nil for empty body" do
      req = Whoosh::Request.new(build_env)
      expect(req.body).to be_nil
    end
  end

  describe "#headers" do
    it "returns request headers" do
      req = Whoosh::Request.new(build_env(headers: { "X-Api-Key" => "secret" }))
      expect(req.headers["X-Api-Key"]).to eq("secret")
    end
  end

  describe "#id" do
    it "returns X-Request-ID if present" do
      req = Whoosh::Request.new(build_env(headers: { "X-Request-Id" => "abc-123" }))
      expect(req.id).to eq("abc-123")
    end

    it "generates a request ID if not present" do
      req = Whoosh::Request.new(build_env)
      expect(req.id).to match(/\A[a-f0-9-]+\z/)
    end
  end

  describe "#query_params" do
    it "parses query string" do
      req = Whoosh::Request.new(build_env(path: "/test?page=2&limit=10"))
      expect(req.query_params["page"]).to eq("2")
      expect(req.query_params["limit"]).to eq("10")
    end
  end
end
