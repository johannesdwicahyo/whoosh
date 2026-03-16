# spec/edge_cases/request_router_edge_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Request edge cases" do
  def build_env(**opts)
    Rack::MockRequest.env_for("/test", **opts)
  end

  it "handles empty JSON body" do
    env = build_env(method: "POST", input: "", "CONTENT_TYPE" => "application/json")
    req = Whoosh::Request.new(env)
    expect(req.body).to be_nil
  end

  it "handles malformed JSON body" do
    env = build_env(method: "POST", input: "{not json", "CONTENT_TYPE" => "application/json")
    req = Whoosh::Request.new(env)
    expect { req.body }.to raise_error(JSON::ParserError)
  end

  it "handles binary body without content-type" do
    env = build_env(method: "POST", input: "\x00\x01\x02")
    req = Whoosh::Request.new(env)
    expect(req.body).to eq("\x00\x01\x02")
  end

  it "handles empty query string" do
    env = Rack::MockRequest.env_for("/test?")
    req = Whoosh::Request.new(env)
    expect(req.query_params).to eq({})
  end

  it "handles very long headers" do
    env = build_env
    env["HTTP_X_LONG"] = "x" * 10_000
    req = Whoosh::Request.new(env)
    expect(req.headers["X-Long"].length).to eq(10_000)
  end
end

RSpec.describe "Router edge cases" do
  let(:router) { Whoosh::Router.new }

  it "handles root path" do
    handler = -> { "root" }
    router.add("GET", "/", handler)
    match = router.match("GET", "/")
    expect(match[:handler]).to eq(handler)
  end

  it "handles deeply nested paths" do
    handler = -> { "deep" }
    router.add("GET", "/a/b/c/d/e/f/g", handler)
    expect(router.match("GET", "/a/b/c/d/e/f/g")[:handler]).to eq(handler)
  end

  it "handles overlapping param routes" do
    router.add("GET", "/users/:id", -> { "user" })
    router.add("GET", "/users/:id/posts", -> { "posts" })
    expect(router.match("GET", "/users/42")[:params][:id]).to eq("42")
    expect(router.match("GET", "/users/42/posts")).not_to be_nil
  end

  it "handles special characters in param values" do
    router.add("GET", "/files/:name", -> { "file" })
    match = router.match("GET", "/files/my-file.txt")
    expect(match[:params][:name]).to eq("my-file.txt")
  end

  it "returns nil for empty path" do
    router.add("GET", "/health", -> { "ok" })
    expect(router.match("GET", "")).to be_nil
  end

  it "handles trailing slash as different route" do
    router.add("GET", "/health", -> { "ok" })
    expect(router.match("GET", "/health/")).to be_nil
  end
end
