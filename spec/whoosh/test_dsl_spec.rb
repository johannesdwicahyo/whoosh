# spec/whoosh/test_dsl_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh/test"

RSpec.describe Whoosh::Test do
  include Whoosh::Test

  let(:application) do
    app = Whoosh::App.new
    app.auth { api_key header: "X-Api-Key", keys: { "sk-test" => { role: :standard } } }
    app.get("/health") { { status: "ok" } }
    app.post("/users") { |req| { name: req.body["name"], created: true } }
    app.get("/protected", auth: :api_key) { |req| { key: req.env["whoosh.auth"][:key] } }
    app
  end

  def app = application.to_rack

  describe "post_json" do
    it "sends JSON body with correct content-type" do
      post_json "/users", { name: "Alice" }
      assert_response 200
      assert_json(name: "Alice", created: true)
    end
  end

  describe "assert_response" do
    it "asserts status code" do
      get "/health"
      assert_response 200
    end
  end

  describe "assert_json" do
    it "asserts JSON body fields" do
      get "/health"
      assert_json(status: "ok")
    end
  end

  describe "assert_json_path" do
    it "asserts nested JSON paths" do
      get "/health"
      assert_json_path "status", "ok"
    end
  end

  describe "assert_json_includes" do
    it "checks key existence" do
      get "/health"
      assert_json_includes :status
    end
  end

  describe "response_json" do
    it "returns parsed JSON body" do
      get "/health"
      expect(response_json["status"]).to eq("ok")
    end
  end

  describe "get_with_auth" do
    it "sends request with API key" do
      get_with_auth "/protected", key: "sk-test"
      assert_response 200
      assert_json(key: "sk-test")
    end
  end

  describe "post_with_auth" do
    it "sends JSON with API key" do
      post_with_auth "/users", { name: "Bob" }, key: "sk-test"
      assert_response 200
    end
  end
end
