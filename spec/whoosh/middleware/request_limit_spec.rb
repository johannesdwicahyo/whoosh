# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Middleware::RequestLimit do
  let(:inner_app) { ->(env) { [200, {}, ["OK"]] } }

  it "passes requests under the limit" do
    app = Whoosh::Middleware::RequestLimit.new(inner_app, max_bytes: 1_048_576)
    env = Rack::MockRequest.env_for("/test", method: "POST", input: "small body")
    status, _, _ = app.call(env)
    expect(status).to eq(200)
  end

  it "rejects requests over the limit" do
    app = Whoosh::Middleware::RequestLimit.new(inner_app, max_bytes: 10)
    env = Rack::MockRequest.env_for("/test", method: "POST", input: "x" * 100)
    status, _, body = app.call(env)
    expect(status).to eq(413)
    parsed = JSON.parse(body.first)
    expect(parsed["error"]).to eq("request_too_large")
  end
end
