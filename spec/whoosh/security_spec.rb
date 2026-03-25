# spec/whoosh/security_spec.rb
# frozen_string_literal: true
require "spec_helper"
require "rack/test"

RSpec.describe "Security" do
  include Rack::Test::Methods
  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  before { application.get("/test") { { ok: true } } }

  it "includes CSP header" do
    get "/test"
    expect(last_response.headers["content-security-policy"]).to include("default-src")
  end

  it "includes all security headers" do
    get "/test"
    %w[x-content-type-options x-frame-options strict-transport-security referrer-policy content-security-policy].each do |h|
      expect(last_response.headers[h]).not_to be_nil, "Missing: #{h}"
    end
  end
end
