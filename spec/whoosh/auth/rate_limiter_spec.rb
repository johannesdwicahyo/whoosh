# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Auth::RateLimiter do
  describe "#check!" do
    it "allows requests under the limit" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 5, default_period: 60)
      expect { limiter.check!("key-1", "/test") }.not_to raise_error
    end

    it "raises RateLimitExceeded when over limit" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 2, default_period: 60)
      2.times { limiter.check!("key-1", "/test") }
      expect { limiter.check!("key-1", "/test") }.to raise_error(Whoosh::Errors::RateLimitExceeded)
    end

    it "tracks limits per key independently" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 2, default_period: 60)
      2.times { limiter.check!("key-1", "/test") }
      expect { limiter.check!("key-2", "/test") }.not_to raise_error
    end
  end

  describe "per-endpoint rules" do
    it "applies endpoint-specific limits" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 100, default_period: 60)
      limiter.rule("/chat", limit: 2, period: 60)
      2.times { limiter.check!("key-1", "/chat") }
      expect { limiter.check!("key-1", "/chat") }.to raise_error(Whoosh::Errors::RateLimitExceeded)
      expect { limiter.check!("key-1", "/other") }.not_to raise_error
    end
  end

  describe "tier support" do
    it "applies tier-based limits" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 10, default_period: 60)
      limiter.tier(:free, limit: 2, period: 60)
      limiter.tier(:enterprise, unlimited: true)

      2.times { limiter.check!("key-1", "/test", tier: :free) }
      expect { limiter.check!("key-1", "/test", tier: :free) }.to raise_error(Whoosh::Errors::RateLimitExceeded)
      200.times { limiter.check!("key-2", "/test", tier: :enterprise) }
    end
  end

  describe "fail-open/fail-closed" do
    it "allows on fail-open when store fails" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 5, default_period: 60, on_store_failure: :fail_open)
      limiter.instance_variable_set(:@store, nil)
      expect { limiter.check!("key-1", "/test") }.not_to raise_error
    end

    it "denies on fail-closed when store fails" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 5, default_period: 60, on_store_failure: :fail_closed)
      limiter.instance_variable_set(:@store, nil)
      expect { limiter.check!("key-1", "/test") }.to raise_error(Whoosh::Errors::RateLimitExceeded)
    end
  end

  describe "#remaining" do
    it "returns remaining requests for a key" do
      limiter = Whoosh::Auth::RateLimiter.new(default_limit: 5, default_period: 60)
      3.times { limiter.check!("key-1", "/test") }
      expect(limiter.remaining("key-1", "/test")).to eq(2)
    end
  end
end
