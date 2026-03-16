# spec/whoosh/app_cache_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App cache integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  it "provides cache via DI" do
    application.get "/cached" do |req, cache:|
      result = cache.fetch("greeting", ttl: 60) { "hello" }
      { greeting: result }
    end

    get "/cached"
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)["greeting"]).to eq("hello")
  end

  it "cache persists across requests" do
    call_count = 0
    application.get "/counted" do |req, cache:|
      result = cache.fetch("count") { call_count += 1; call_count }
      { count: result }
    end

    get "/counted"
    get "/counted"
    expect(call_count).to eq(1) # Only computed once
  end
end
