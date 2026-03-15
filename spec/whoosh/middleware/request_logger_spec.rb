# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Whoosh::Middleware::RequestLogger do
  let(:output) { StringIO.new }
  let(:logger) { Whoosh::Logger.new(output: output, format: :json, level: :info) }
  let(:inner_app) { ->(env) { [200, {}, ["OK"]] } }
  let(:app) { Whoosh::Middleware::RequestLogger.new(inner_app, logger: logger) }

  it "logs request method, path, status, and duration" do
    env = Rack::MockRequest.env_for("/test", method: "GET")
    app.call(env)

    output.rewind
    parsed = JSON.parse(output.read)
    expect(parsed["event"]).to eq("request_complete")
    expect(parsed["method"]).to eq("GET")
    expect(parsed["path"]).to eq("/test")
    expect(parsed["status"]).to eq(200)
    expect(parsed["duration_ms"]).to be_a(Numeric)
  end

  it "includes request_id from header" do
    env = Rack::MockRequest.env_for("/test", "HTTP_X_REQUEST_ID" => "abc-123")
    app.call(env)

    output.rewind
    parsed = JSON.parse(output.read)
    expect(parsed["request_id"]).to eq("abc-123")
  end

  it "passes response through unchanged" do
    env = Rack::MockRequest.env_for("/test")
    status, _, body = app.call(env)
    expect(status).to eq(200)
    expect(body).to eq(["OK"])
  end
end
