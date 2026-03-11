# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Middleware::Cors do
  let(:inner_app) { ->(env) { [200, {}, ["OK"]] } }

  describe "with default config" do
    let(:app) { Whoosh::Middleware::Cors.new(inner_app) }

    it "adds CORS headers" do
      env = Rack::MockRequest.env_for("/test", "HTTP_ORIGIN" => "http://example.com")
      _, headers, _ = app.call(env)
      expect(headers["access-control-allow-origin"]).to eq("*")
    end

    it "handles preflight OPTIONS request" do
      env = Rack::MockRequest.env_for("/test",
        method: "OPTIONS",
        "HTTP_ORIGIN" => "http://example.com",
        "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "POST"
      )
      status, headers, _ = app.call(env)
      expect(status).to eq(204)
      expect(headers["access-control-allow-methods"]).to include("POST")
    end
  end

  describe "with custom origins" do
    let(:app) { Whoosh::Middleware::Cors.new(inner_app, origins: ["http://myapp.com"]) }

    it "allows specified origin" do
      env = Rack::MockRequest.env_for("/test", "HTTP_ORIGIN" => "http://myapp.com")
      _, headers, _ = app.call(env)
      expect(headers["access-control-allow-origin"]).to eq("http://myapp.com")
    end

    it "denies unspecified origin" do
      env = Rack::MockRequest.env_for("/test", "HTTP_ORIGIN" => "http://evil.com")
      _, headers, _ = app.call(env)
      expect(headers["access-control-allow-origin"]).to be_nil
    end
  end
end
