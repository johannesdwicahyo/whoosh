# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "Request ID propagation" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  before do
    application.get "/check-id" do |req|
      { request_id: req.id }
    end
  end

  it "generates a request ID when none provided" do
    get "/check-id"
    body = JSON.parse(last_response.body)
    expect(body["request_id"]).to match(/\A[a-f0-9-]+\z/)
  end

  it "uses X-Request-Id header when provided" do
    get "/check-id", {}, { "HTTP_X_REQUEST_ID" => "custom-id-123" }
    body = JSON.parse(last_response.body)
    expect(body["request_id"]).to eq("custom-id-123")
  end

  it "echoes request ID in response header" do
    get "/check-id"
    expect(last_response.headers["x-request-id"]).to match(/\A[a-f0-9-]+\z/)
  end

  it "echoes provided request ID in response" do
    get "/check-id", {}, { "HTTP_X_REQUEST_ID" => "echo-me" }
    expect(last_response.headers["x-request-id"]).to eq("echo-me")
  end
end
