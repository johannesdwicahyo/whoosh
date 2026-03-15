# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::OpenAPI::UI do
  describe ".swagger_html" do
    it "returns HTML with Swagger UI" do
      html = Whoosh::OpenAPI::UI.swagger_html("/openapi.json")
      expect(html).to include("swagger-ui")
      expect(html).to include("/openapi.json")
      expect(html).to include("<html")
    end
  end

  describe ".rack_response" do
    it "returns a Rack-compatible response" do
      status, headers, body = Whoosh::OpenAPI::UI.rack_response("/openapi.json")
      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("text/html")
      expect(body.first).to include("swagger-ui")
    end
  end
end
