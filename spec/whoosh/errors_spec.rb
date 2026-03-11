# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Errors do
  describe Whoosh::Errors::WhooshError do
    it "is a StandardError" do
      expect(Whoosh::Errors::WhooshError.new("test")).to be_a(StandardError)
    end
  end

  describe Whoosh::Errors::ValidationError do
    it "has status 422" do
      error = Whoosh::Errors::ValidationError.new([{ field: "name", message: "is required" }])
      expect(error.status).to eq(422)
    end

    it "has error type" do
      error = Whoosh::Errors::ValidationError.new([])
      expect(error.error_type).to eq("validation_failed")
    end

    it "stores details" do
      details = [{ field: "age", message: "must be positive", value: -1 }]
      error = Whoosh::Errors::ValidationError.new(details)
      expect(error.details).to eq(details)
    end

    it "serializes to JSON hash" do
      details = [{ field: "age", message: "must be positive" }]
      error = Whoosh::Errors::ValidationError.new(details)
      expect(error.to_h).to eq({ error: "validation_failed", details: details })
    end
  end

  describe Whoosh::Errors::NotFoundError do
    it "has status 404" do
      expect(Whoosh::Errors::NotFoundError.new.status).to eq(404)
    end
  end

  describe Whoosh::Errors::UnauthorizedError do
    it "has status 401" do
      expect(Whoosh::Errors::UnauthorizedError.new.status).to eq(401)
    end
  end

  describe Whoosh::Errors::ForbiddenError do
    it "has status 403" do
      expect(Whoosh::Errors::ForbiddenError.new.status).to eq(403)
    end
  end

  describe Whoosh::Errors::RateLimitExceeded do
    it "has status 429" do
      error = Whoosh::Errors::RateLimitExceeded.new(retry_after: 60)
      expect(error.status).to eq(429)
    end

    it "stores retry_after" do
      error = Whoosh::Errors::RateLimitExceeded.new(retry_after: 60)
      expect(error.retry_after).to eq(60)
    end
  end

  describe Whoosh::Errors::DependencyError do
    it "is a WhooshError" do
      expect(Whoosh::Errors::DependencyError.new("circular")).to be_a(Whoosh::Errors::WhooshError)
    end
  end
end
