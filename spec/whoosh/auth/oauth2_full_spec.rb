# spec/whoosh/auth/oauth2_full_spec.rb
# frozen_string_literal: true
require "spec_helper"

RSpec.describe Whoosh::Auth::OAuth2 do
  describe "provider defaults" do
    it "sets Google URLs" do
      auth = Whoosh::Auth::OAuth2.new(provider: :google, client_id: "id", redirect_uri: "http://localhost/cb")
      url = auth.authorize_url
      expect(url).to include("accounts.google.com")
      expect(url).to include("client_id=id")
    end

    it "sets GitHub URLs" do
      auth = Whoosh::Auth::OAuth2.new(provider: :github, client_id: "id", redirect_uri: "http://localhost/cb")
      expect(auth.authorize_url).to include("github.com")
    end
  end

  describe "#authorize_url" do
    it "builds URL with params" do
      auth = Whoosh::Auth::OAuth2.new(
        provider: :google, client_id: "abc", redirect_uri: "http://localhost/cb", scopes: ["email", "profile"]
      )
      url = auth.authorize_url(state: "xyz")
      expect(url).to include("client_id=abc")
      expect(url).to include("redirect_uri=")
      expect(url).to include("state=xyz")
      expect(url).to include("scope=email+profile")
    end
  end

  describe "#authenticate" do
    it "extracts Bearer token" do
      auth = Whoosh::Auth::OAuth2.new
      env = Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => "Bearer my-token")
      req = Whoosh::Request.new(env)
      result = auth.authenticate(req)
      expect(result[:token]).to eq("my-token")
    end

    it "uses custom validator" do
      auth = Whoosh::Auth::OAuth2.new(validator: -> (t) { { user_id: 1 } if t == "valid" })
      env = Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => "Bearer valid")
      result = auth.authenticate(Whoosh::Request.new(env))
      expect(result[:user_id]).to eq(1)
    end

    it "raises for missing header" do
      auth = Whoosh::Auth::OAuth2.new
      req = Whoosh::Request.new(Rack::MockRequest.env_for("/"))
      expect { auth.authenticate(req) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end
  end
end
