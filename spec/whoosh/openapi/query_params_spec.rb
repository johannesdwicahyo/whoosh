# spec/whoosh/openapi/query_params_spec.rb
# frozen_string_literal: true
require "spec_helper"
require "rack/test"

class UserFilterSchema < Whoosh::Schema
  field :page, Integer, desc: "Page number"
  field :search, String, desc: "Search term"
end

RSpec.describe "OpenAPI query params" do
  include Rack::Test::Methods
  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  before do
    application.get "/users", query: UserFilterSchema do |req|
      { users: [], page: req.query_params["page"] }
    end
  end

  it "documents query params in OpenAPI" do
    get "/openapi.json"
    spec = JSON.parse(last_response.body)
    params = spec["paths"]["/users"]["get"]["parameters"]
    expect(params).to be_an(Array)
    names = params.map { |p| p["name"] }
    expect(names).to include("page")
    expect(names).to include("search")
  end

  it "marks params as query type" do
    get "/openapi.json"
    spec = JSON.parse(last_response.body)
    param = spec["paths"]["/users"]["get"]["parameters"].find { |p| p["name"] == "page" }
    expect(param["in"]).to eq("query")
  end
end
