# spec/whoosh/app_metrics_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App metrics integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  before do
    application.get "/health" do
      { status: "ok" }
    end
  end

  it "serves /metrics endpoint" do
    get "/health"  # generate some traffic
    get "/health"

    get "/metrics"
    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("whoosh_requests_total")
  end

  it "tracks request counts" do
    get "/health"
    get "/metrics"
    expect(last_response.body).to include("whoosh_requests_total")
  end

  it "tracks request duration" do
    get "/health"
    get "/metrics"
    expect(last_response.body).to include("whoosh_request_duration_seconds")
  end
end
