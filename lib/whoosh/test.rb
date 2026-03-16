# lib/whoosh/test.rb
# frozen_string_literal: true

require "rack/test"
require "json"

module Whoosh
  module Test
    include Rack::Test::Methods

    # Override in your test class to return the Rack app
    def app
      raise NotImplementedError, "Define #app in your test class to return a Rack app"
    end

    # --- Request helpers ---

    def post_json(path, body = {}, headers: {})
      merged_headers = { "CONTENT_TYPE" => "application/json" }.merge(headers)
      post path, JSON.generate(body), merged_headers
    end

    def put_json(path, body = {}, headers: {})
      merged_headers = { "CONTENT_TYPE" => "application/json" }.merge(headers)
      put path, JSON.generate(body), merged_headers
    end

    def patch_json(path, body = {}, headers: {})
      merged_headers = { "CONTENT_TYPE" => "application/json" }.merge(headers)
      patch path, JSON.generate(body), merged_headers
    end

    def get_with_auth(path, key:, header: "HTTP_X_API_KEY")
      get path, {}, { header => key }
    end

    def post_with_auth(path, body = {}, key:, header: "HTTP_X_API_KEY")
      post path, JSON.generate(body), { "CONTENT_TYPE" => "application/json", header => key }
    end

    # --- Response assertions ---

    def assert_response(expected_status)
      expect(last_response.status).to eq(expected_status)
    end

    def assert_json(expected_hash)
      body = JSON.parse(last_response.body)
      expected_hash.each do |key, value|
        expect(body[key.to_s]).to eq(value)
      end
    end

    def assert_json_path(path, expected_value)
      body = JSON.parse(last_response.body)
      keys = path.to_s.split(".")
      value = keys.reduce(body) { |h, k| h.is_a?(Hash) ? h[k] : nil }
      expect(value).to eq(expected_value)
    end

    def assert_json_includes(key)
      body = JSON.parse(last_response.body)
      expect(body).to have_key(key.to_s)
    end

    def response_json
      JSON.parse(last_response.body)
    end
  end
end
