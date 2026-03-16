# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "Health check" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "default /healthz" do
    before do
      application.health_check
      application.get("/test") { { ok: true } }
    end

    it "returns 200 with status ok" do
      get "/healthz"
      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("ok")
    end

    it "includes version" do
      get "/healthz"
      body = JSON.parse(last_response.body)
      expect(body["version"]).to eq(Whoosh::VERSION)
    end
  end

  describe "with probes" do
    it "reports passing probes" do
      application.health_check do
        probe(:database) { true }
        probe(:cache) { true }
      end
      application.get("/x") { {} }

      get "/healthz"
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("ok")
      expect(body["checks"]["database"]).to eq("ok")
    end

    it "returns 503 if probe fails" do
      application.health_check do
        probe(:database) { true }
        probe(:cache) { raise "connection refused" }
      end
      application.get("/x") { {} }

      get "/healthz"
      expect(last_response.status).to eq(503)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("degraded")
      expect(body["checks"]["cache"]).to include("fail")
    end
  end
end
