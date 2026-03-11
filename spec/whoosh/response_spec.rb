# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Response do
  describe ".json" do
    it "creates a JSON response" do
      status, headers, body = Whoosh::Response.json({ name: "test" })
      expect(status).to eq(200)
      expect(headers["content-type"]).to eq("application/json")
      parsed = JSON.parse(body.first)
      expect(parsed["name"]).to eq("test")
    end

    it "accepts a custom status" do
      status, _, _ = Whoosh::Response.json({ created: true }, status: 201)
      expect(status).to eq(201)
    end
  end

  describe ".error" do
    it "creates an error response from HttpError" do
      error = Whoosh::Errors::ValidationError.new([{ field: "name", message: "required" }])
      status, headers, body = Whoosh::Response.error(error)
      expect(status).to eq(422)
      expect(headers["content-type"]).to eq("application/json")
      parsed = JSON.parse(body.first)
      expect(parsed["error"]).to eq("validation_failed")
    end

    it "includes Retry-After for rate limit errors" do
      error = Whoosh::Errors::RateLimitExceeded.new(retry_after: 120)
      _, headers, _ = Whoosh::Response.error(error)
      expect(headers["retry-after"]).to eq("120")
    end
  end

  describe ".not_found" do
    it "returns 404" do
      status, _, body = Whoosh::Response.not_found
      expect(status).to eq(404)
      parsed = JSON.parse(body.first)
      expect(parsed["error"]).to eq("not_found")
    end
  end
end
