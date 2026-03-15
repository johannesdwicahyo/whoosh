# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::ApiKey do
  describe "#authenticate" do
    it "returns the key when valid" do
      auth = Whoosh::Auth::ApiKey.new(keys: { "sk-test-123" => { role: :standard } }, header: "X-Api-Key")
      env = Rack::MockRequest.env_for("/test", "HTTP_X_API_KEY" => "sk-test-123")
      request = Whoosh::Request.new(env)
      result = auth.authenticate(request)
      expect(result).to eq({ key: "sk-test-123", role: :standard })
    end

    it "raises UnauthorizedError when key is missing" do
      auth = Whoosh::Auth::ApiKey.new(keys: { "sk-test-123" => { role: :standard } }, header: "X-Api-Key")
      env = Rack::MockRequest.env_for("/test")
      request = Whoosh::Request.new(env)
      expect { auth.authenticate(request) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end

    it "raises UnauthorizedError when key is invalid" do
      auth = Whoosh::Auth::ApiKey.new(keys: { "sk-test-123" => { role: :standard } }, header: "X-Api-Key")
      env = Rack::MockRequest.env_for("/test", "HTTP_X_API_KEY" => "sk-bad")
      request = Whoosh::Request.new(env)
      expect { auth.authenticate(request) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end

    it "supports Bearer prefix stripping" do
      auth = Whoosh::Auth::ApiKey.new(keys: { "my-key" => { role: :admin } }, header: "Authorization")
      env = Rack::MockRequest.env_for("/test", "HTTP_AUTHORIZATION" => "Bearer my-key")
      request = Whoosh::Request.new(env)
      result = auth.authenticate(request)
      expect(result[:key]).to eq("my-key")
    end
  end

  describe "#register_key" do
    it "adds a key at runtime" do
      auth = Whoosh::Auth::ApiKey.new(keys: {})
      auth.register_key("sk-new", role: :basic)
      env = Rack::MockRequest.env_for("/test", "HTTP_X_API_KEY" => "sk-new")
      request = Whoosh::Request.new(env)
      result = auth.authenticate(request)
      expect(result[:role]).to eq(:basic)
    end
  end
end
