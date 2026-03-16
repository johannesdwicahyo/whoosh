# spec/whoosh/response_validation_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "stringio"

class ResponseTestSchema < Whoosh::Schema
  field :name, String, required: true
end

RSpec.describe "Response schema validation" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  it "logs warning when response doesn't match schema" do
    application.post "/test", response: ResponseTestSchema do |req|
      { wrong_field: "no name field" }  # Missing :name
    end

    post "/test", {}.to_json, "CONTENT_TYPE" => "application/json"
    # Should still return 200 (validation is advisory, not blocking)
    expect(last_response.status).to eq(200)
  end

  it "passes when response matches schema" do
    application.post "/test", response: ResponseTestSchema do |req|
      { name: "Alice" }
    end

    post "/test", {}.to_json, "CONTENT_TYPE" => "application/json"
    expect(last_response.status).to eq(200)
  end
end
