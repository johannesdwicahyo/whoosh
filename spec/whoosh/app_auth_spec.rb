# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App auth integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "API key auth on routes" do
    before do
      application.auth do
        api_key header: "X-Api-Key", keys: { "sk-valid" => { role: :standard } }
      end

      application.get "/public" do
        { open: true }
      end

      application.get "/protected", auth: :api_key do |req|
        { user: req.env["whoosh.auth"][:key] }
      end
    end

    it "allows unauthenticated access to public routes" do
      get "/public"
      expect(last_response.status).to eq(200)
    end

    it "allows authenticated access to protected routes" do
      get "/protected", {}, { "HTTP_X_API_KEY" => "sk-valid" }
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["user"]).to eq("sk-valid")
    end

    it "returns 401 for unauthenticated access to protected routes" do
      get "/protected"
      expect(last_response.status).to eq(401)
    end

    it "returns 401 for invalid key on protected routes" do
      get "/protected", {}, { "HTTP_X_API_KEY" => "sk-bad" }
      expect(last_response.status).to eq(401)
    end
  end

  describe "rate limiting DSL" do
    before do
      application.rate_limit do
        default limit: 3, period: 60
        rule "/limited", limit: 2, period: 60
      end

      application.get "/limited" do
        { ok: true }
      end
    end

    it "allows requests under the limit" do
      2.times { get "/limited" }
      expect(last_response.status).to eq(200)
    end

    it "returns 429 when over limit" do
      3.times { get "/limited" }
      expect(last_response.status).to eq(429)
    end
  end

  describe "access control DSL" do
    it "registers roles" do
      application.access_control do
        role :basic, models: ["claude-haiku"]
        role :premium, models: ["claude-haiku", "claude-opus"]
      end

      expect(application.acl.models_for(:basic)).to eq(["claude-haiku"])
      expect(application.acl.models_for(:premium)).to include("claude-opus")
    end
  end

  describe "token tracking DSL" do
    it "registers callbacks" do
      events = []
      application.token_tracking do
        on_usage do |key, endpoint, tokens|
          events << { key: key, endpoint: endpoint, tokens: tokens }
        end
      end

      application.token_tracker.record(key: "sk-1", endpoint: "/chat", tokens: { prompt: 50, completion: 100 })
      expect(events.length).to eq(1)
    end
  end
end
