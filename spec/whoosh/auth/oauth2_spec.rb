# spec/whoosh/auth/oauth2_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::OAuth2 do
  describe "#authenticate" do
    it "extracts Bearer token" do
      auth = Whoosh::Auth::OAuth2.new
      env = Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => "Bearer my-token")
      req = Whoosh::Request.new(env)
      result = auth.authenticate(req)
      expect(result[:token]).to eq("my-token")
    end

    it "raises for missing header" do
      auth = Whoosh::Auth::OAuth2.new
      env = Rack::MockRequest.env_for("/")
      req = Whoosh::Request.new(env)
      expect { auth.authenticate(req) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end

    it "calls custom validator" do
      validator = -> (token) { { user_id: 42 } if token == "valid" }
      auth = Whoosh::Auth::OAuth2.new(validator: validator)
      env = Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => "Bearer valid")
      req = Whoosh::Request.new(env)
      expect(auth.authenticate(req)[:user_id]).to eq(42)
    end

    it "rejects invalid token via validator" do
      validator = -> (token) { nil }
      auth = Whoosh::Auth::OAuth2.new(validator: validator)
      env = Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => "Bearer bad")
      req = Whoosh::Request.new(env)
      expect { auth.authenticate(req) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end
  end
end
