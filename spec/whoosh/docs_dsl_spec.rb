# spec/whoosh/docs_dsl_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "Docs DSL" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  describe "app.docs" do
    before do
      application.docs enabled: true, redoc: true
      application.get("/test") { { ok: true } }
    end

    it "serves /docs" do
      get "/docs"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("swagger-ui")
    end

    it "serves /redoc when enabled" do
      get "/redoc"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("redoc")
    end
  end
end

RSpec.describe "OpenAPI::UI" do
  describe ".redoc_html" do
    it "returns HTML with ReDoc" do
      html = Whoosh::OpenAPI::UI.redoc_html("/openapi.json")
      expect(html).to include("redoc")
      expect(html).to include("/openapi.json")
    end
  end
end
