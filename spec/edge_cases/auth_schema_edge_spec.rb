# spec/edge_cases/auth_schema_edge_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "API Key edge cases" do
  let(:auth) { Whoosh::Auth::ApiKey.new(keys: { "sk-valid" => { role: :basic } }, header: "X-Api-Key") }

  it "rejects empty header value" do
    env = Rack::MockRequest.env_for("/test", "HTTP_X_API_KEY" => "")
    req = Whoosh::Request.new(env)
    expect { auth.authenticate(req) }.to raise_error(Whoosh::Errors::UnauthorizedError)
  end

  it "rejects whitespace-only key" do
    env = Rack::MockRequest.env_for("/test", "HTTP_X_API_KEY" => "   ")
    req = Whoosh::Request.new(env)
    expect { auth.authenticate(req) }.to raise_error(Whoosh::Errors::UnauthorizedError)
  end
end

RSpec.describe "JWT edge cases" do
  let(:auth) { Whoosh::Auth::Jwt.new(secret: "test-secret-32-chars-long!!!!!!!", algorithm: :hs256) }

  it "rejects token with wrong segment count" do
    env = Rack::MockRequest.env_for("/test", "HTTP_AUTHORIZATION" => "Bearer only.two")
    req = Whoosh::Request.new(env)
    expect { auth.authenticate(req) }.to raise_error(Whoosh::Errors::UnauthorizedError)
  end

  it "rejects tampered payload" do
    token = auth.generate(sub: "user-1")
    parts = token.split(".")
    parts[1] = Base64.urlsafe_encode64('{"sub":"hacker","iat":9999999999,"exp":9999999999}', padding: false)
    tampered = parts.join(".")
    env = Rack::MockRequest.env_for("/test", "HTTP_AUTHORIZATION" => "Bearer #{tampered}")
    req = Whoosh::Request.new(env)
    expect { auth.authenticate(req) }.to raise_error(Whoosh::Errors::UnauthorizedError)
  end
end

RSpec.describe "RateLimiter edge cases" do
  it "resets after window expires" do
    limiter = Whoosh::Auth::RateLimiter.new(default_limit: 2, default_period: 0.1)
    2.times { limiter.check!("key", "/test") }
    expect { limiter.check!("key", "/test") }.to raise_error(Whoosh::Errors::RateLimitExceeded)
    sleep 0.15
    expect { limiter.check!("key", "/test") }.not_to raise_error
  end
end

class EdgeEmptySchema < Whoosh::Schema; end

class EdgeTestSchema < Whoosh::Schema
  field :name, String, required: true
  field :age, Integer
end

RSpec.describe "Schema edge cases" do
  it "validates empty schema with any data" do
    result = EdgeEmptySchema.validate({ anything: "goes" })
    expect(result).to be_success
  end

  it "handles nil input" do
    result = EdgeTestSchema.validate(nil)
    expect(result).not_to be_success
  end

  it "handles string keys" do
    result = EdgeTestSchema.validate({ "name" => "Alice" })
    expect(result).to be_success
  end

  it "ignores extra fields" do
    result = EdgeTestSchema.validate({ name: "Alice", unknown: "field" })
    expect(result).to be_success
  end

  it "handles very long string values" do
    result = EdgeTestSchema.validate({ name: "x" * 100_000 })
    expect(result).to be_success
  end
end
