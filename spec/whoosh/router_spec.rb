# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Router do
  let(:router) { Whoosh::Router.new }

  describe "#add and #match" do
    it "matches a simple route" do
      handler = -> { "hello" }
      router.add("GET", "/health", handler)

      match = router.match("GET", "/health")
      expect(match).not_to be_nil
      expect(match[:handler]).to eq(handler)
      expect(match[:params]).to be_empty
    end

    it "matches route with path params" do
      handler = -> { "user" }
      router.add("GET", "/users/:id", handler)

      match = router.match("GET", "/users/42")
      expect(match[:handler]).to eq(handler)
      expect(match[:params]).to eq({ id: "42" })
    end

    it "matches route with multiple path params" do
      handler = -> { "comment" }
      router.add("GET", "/users/:user_id/posts/:post_id", handler)

      match = router.match("GET", "/users/1/posts/99")
      expect(match[:params]).to eq({ user_id: "1", post_id: "99" })
    end

    it "returns nil for no match" do
      router.add("GET", "/health", -> { "ok" })
      expect(router.match("GET", "/missing")).to be_nil
    end

    it "differentiates HTTP methods" do
      get_handler = -> { "get" }
      post_handler = -> { "post" }
      router.add("GET", "/items", get_handler)
      router.add("POST", "/items", post_handler)

      expect(router.match("GET", "/items")[:handler]).to eq(get_handler)
      expect(router.match("POST", "/items")[:handler]).to eq(post_handler)
    end

    it "stores route metadata" do
      handler = -> { "ok" }
      router.add("POST", "/chat", handler, request_schema: "ChatRequest", mcp: true)

      match = router.match("POST", "/chat")
      expect(match[:metadata][:request_schema]).to eq("ChatRequest")
      expect(match[:metadata][:mcp]).to be true
    end
  end

  describe "#routes" do
    it "returns all registered routes" do
      router.add("GET", "/a", -> {})
      router.add("POST", "/b", -> {})

      routes = router.routes
      expect(routes.length).to eq(2)
      expect(routes.map { |r| r[:method] }).to contain_exactly("GET", "POST")
      expect(routes.map { |r| r[:path] }).to contain_exactly("/a", "/b")
    end
  end

  describe "#freeze!" do
    it "prevents adding new routes after freeze" do
      router.add("GET", "/a", -> {})
      router.freeze!

      expect { router.add("GET", "/b", -> {}) }.to raise_error(RuntimeError, /frozen/)
    end

    it "still matches after freeze" do
      handler = -> { "ok" }
      router.add("GET", "/a", handler)
      router.freeze!

      expect(router.match("GET", "/a")[:handler]).to eq(handler)
    end
  end
end
