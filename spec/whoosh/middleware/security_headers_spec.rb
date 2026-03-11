# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Middleware::SecurityHeaders do
  let(:inner_app) { ->(env) { [200, {}, ["OK"]] } }
  let(:app) { Whoosh::Middleware::SecurityHeaders.new(inner_app) }

  it "adds X-Content-Type-Options" do
    env = Rack::MockRequest.env_for("/test")
    _, headers, _ = app.call(env)
    expect(headers["x-content-type-options"]).to eq("nosniff")
  end

  it "adds X-Frame-Options" do
    env = Rack::MockRequest.env_for("/test")
    _, headers, _ = app.call(env)
    expect(headers["x-frame-options"]).to eq("DENY")
  end

  it "adds X-XSS-Protection" do
    env = Rack::MockRequest.env_for("/test")
    _, headers, _ = app.call(env)
    expect(headers["x-xss-protection"]).to eq("1; mode=block")
  end

  it "adds Strict-Transport-Security" do
    env = Rack::MockRequest.env_for("/test")
    _, headers, _ = app.call(env)
    expect(headers["strict-transport-security"]).to eq("max-age=31536000; includeSubDomains")
  end
end
