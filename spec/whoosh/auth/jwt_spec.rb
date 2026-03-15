# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::Jwt do
  let(:secret) { "test-secret-key-32chars-long!!!!" }
  let(:auth) { Whoosh::Auth::Jwt.new(secret: secret, algorithm: :hs256) }

  describe "#generate" do
    it "generates a valid JWT token" do
      token = auth.generate(sub: "user-1", role: :standard)
      expect(token).to be_a(String)
      expect(token.split(".").length).to eq(3)
    end
  end

  describe "#authenticate" do
    it "validates and decodes a token" do
      token = auth.generate(sub: "user-1", role: :standard)
      env = Rack::MockRequest.env_for("/test", "HTTP_AUTHORIZATION" => "Bearer #{token}")
      request = Whoosh::Request.new(env)
      result = auth.authenticate(request)
      expect(result[:sub]).to eq("user-1")
      expect(result[:role]).to eq("standard")
    end

    it "raises UnauthorizedError for missing token" do
      env = Rack::MockRequest.env_for("/test")
      request = Whoosh::Request.new(env)
      expect { auth.authenticate(request) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end

    it "raises UnauthorizedError for invalid token" do
      env = Rack::MockRequest.env_for("/test", "HTTP_AUTHORIZATION" => "Bearer invalid.token.here")
      request = Whoosh::Request.new(env)
      expect { auth.authenticate(request) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end

    it "raises UnauthorizedError for expired token" do
      auth_with_expiry = Whoosh::Auth::Jwt.new(secret: secret, algorithm: :hs256, expiry: -1)
      token = auth_with_expiry.generate(sub: "user-1")
      env = Rack::MockRequest.env_for("/test", "HTTP_AUTHORIZATION" => "Bearer #{token}")
      request = Whoosh::Request.new(env)
      expect { auth_with_expiry.authenticate(request) }.to raise_error(Whoosh::Errors::UnauthorizedError, /expired/i)
    end
  end
end
