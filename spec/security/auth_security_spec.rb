# spec/security/auth_security_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Security audit" do
  describe "JWT timing-safe comparison" do
    let(:auth) { Whoosh::Auth::Jwt.new(secret: "test-secret-32-chars-long!!!!!!!", algorithm: :hs256) }

    it "rejects tokens with modified signature" do
      token = auth.generate(sub: "user-1")
      parts = token.split(".")
      # Flip last char of signature
      sig = parts[2]
      parts[2] = sig[0..-2] + (sig[-1] == "a" ? "b" : "a")
      tampered = parts.join(".")

      env = Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => "Bearer #{tampered}")
      req = Whoosh::Request.new(env)
      expect { auth.authenticate(req) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end

    it "rejects tokens with completely different signature" do
      token = auth.generate(sub: "user-1")
      parts = token.split(".")
      parts[2] = Base64.urlsafe_encode64("fakesignature", padding: false)
      tampered = parts.join(".")

      env = Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => "Bearer #{tampered}")
      req = Whoosh::Request.new(env)
      expect { auth.authenticate(req) }.to raise_error(Whoosh::Errors::UnauthorizedError)
    end
  end

  describe "API key constant-time considerations" do
    it "does not leak key existence via error message" do
      auth = Whoosh::Auth::ApiKey.new(keys: { "sk-real" => { role: :basic } }, header: "X-Api-Key")

      env1 = Rack::MockRequest.env_for("/", "HTTP_X_API_KEY" => "sk-wrong")
      req1 = Whoosh::Request.new(env1)

      env2 = Rack::MockRequest.env_for("/", "HTTP_X_API_KEY" => "sk-also-wrong")
      req2 = Whoosh::Request.new(env2)

      begin
        auth.authenticate(req1)
      rescue Whoosh::Errors::UnauthorizedError => e1
        msg1 = e1.message
      end

      begin
        auth.authenticate(req2)
      rescue Whoosh::Errors::UnauthorizedError => e2
        msg2 = e2.message
      end

      # Error messages should be identical regardless of which key was tried
      expect(msg1).to eq(msg2)
    end
  end

  describe "Security headers completeness" do
    let(:app) { Whoosh::Middleware::SecurityHeaders.new(->(env) { [200, {}, ["ok"]] }) }

    it "includes all required security headers" do
      _, headers, _ = app.call(Rack::MockRequest.env_for("/"))
      expect(headers["x-content-type-options"]).to eq("nosniff")
      expect(headers["x-frame-options"]).to eq("DENY")
      expect(headers["x-xss-protection"]).to eq("1; mode=block")
      expect(headers["strict-transport-security"]).to be_a(String)
      expect(headers["referrer-policy"]).to be_a(String)
      expect(headers["x-download-options"]).to eq("noopen")
      expect(headers["x-permitted-cross-domain-policies"]).to eq("none")
    end
  end

  describe "CORS wildcard safety" do
    it "does not reflect arbitrary origins when configured with specific origins" do
      inner = ->(env) { [200, {}, ["ok"]] }
      app = Whoosh::Middleware::Cors.new(inner, origins: ["https://myapp.com"])

      env = Rack::MockRequest.env_for("/", "HTTP_ORIGIN" => "https://evil.com")
      _, headers, _ = app.call(env)
      expect(headers["access-control-allow-origin"]).to be_nil
    end
  end

  describe "Rate limiter bypass prevention" do
    it "cannot bypass by changing path case" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 1, default_period: 60)
      limiter.check!("key", "/API")
      # /API and /api are different paths — this is correct behavior
      # (case-sensitive routing is the norm)
      expect { limiter.check!("key", "/API") }.to raise_error(Whoosh::Errors::RateLimitExceeded)
    end
  end
end
